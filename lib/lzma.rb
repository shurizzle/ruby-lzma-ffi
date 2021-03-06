#--
# Copyleft shura. [ shura1991@gmail.com ]
#
# This file is part of lzma-ffi.
#
# lzma-ffi is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# lzma-ffi is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with lzma-ffi. If not, see <http://www.gnu.org/licenses/>.
#++

if RUBY_PLATFORM =~ /java/
  require 'java'
  require File.realpath(File.join(__FILE__, '..', 'lzma.jar'))

  class LZMA
    def self.decompress(what, buf_len=4096, &blk)
      bais = what.is_a?(IO) ? what.to_inputstream : Java::java.io.ByteArrayInputStream.new(what.to_s.to_java_bytes)
      lis = Java::net.contrapunctus.lzma.LzmaInputStream.new(bais)
      dis = Java::java.io.DataInputStream.new(lis)
      res = ''
      blk ||= lambda {|chunk| res << chunk }
      expanded, read = Java::byte[buf_len].new, 0

      while (read = dis.read(expanded, 0, buf_len)) > 0
        blk.call(String.from_java_bytes(expanded[0, read]))
      end

      dis.close

      block_given? ? what : res
    end

    def self.extract(file, to=nil, buf_len=4096)
      to ||= file.gsub(/\.(xz|lzma)$/, '')
      File.unlink(to) if File.file?(to)

      bais = Java::java.io.FileInputStream.new(file)
      lis = Java::net.contrapunctus.lzma.LzmaInputStream.new(bais)
      dis = Java::java.io.DataInputStream.new(lis)
      out = Java::java.io.FileOutputStream.new(to)
      expanded, read = Java::byte[buf_len].new, 0

      while (read = dis.read(expanded, 0, buf_len)) > 0
        out.write(expanded[0, read])
      end

      dis.close

      to
    end
  end
else
  require 'ffi'
  require 'stringio'

  class String
    def pointer
      FFI::Pointer.new([self].pack('P').unpack('L!').first)
    end
  end

  class LZMA
    module C
      extend FFI::Library

      if RUBY_PLATFORM =~ /(?<!dar)win|w32/
        case 1.size * 8
        when 64
          ffi_lib File.realpath(File.join('..', 'liblzma_x86_64.dll'), __FILE__)
        when 32
          ffi_lib File.realpath(File.join('..', 'liblzma_x86.dll'), __FILE__)
        else
          raise LoadError, "Windows architecture not supported"
        end
      else
        ffi_lib ['lzma.so.5.0.3', 'lzma.so.5', 'lzma.so', 'lzma']
      end

      enum :lzma_ret, [:OK, 0, :STREAM_END, :NO_CHECK, :UNSUPPORTED_CHECK,
        :GET_CHECK, :MEM_ERROR, :MEMLIMIT_ERROR, :FORMAT_ERROR, :OPTIONS_ERROR,
        :DATA_ERROR, :BUF_ERROR, :PROG_ERROR]

      enum :lzma_action, [:RUN, 0, :SYNC_FLUSH, :FULL_FLUSH, :FINISH]
      enum :lzma_reserved_enum, [:LZMA_RESERVED_ENUM, 0]

      class LZMAStream < FFI::Struct
        layout \
          :next_in, :pointer,
          :avail_in, :size_t,
          :total_in, :uint64,

          :next_out, :pointer,
          :avail_out, :size_t,
          :total_out, :uint64,

          :allocator, :pointer,
          :internal, :pointer,

          :reserved_ptr1, :pointer,
          :reserved_ptr2, :pointer,
          :reserved_ptr3, :pointer,
          :reserved_ptr4, :pointer,
          :reserved_int1, :uint64,
          :reserved_int2, :uint64,
          :reserved_int3, :size_t,
          :reserved_int4, :size_t,
          :reserved_enum1, :lzma_reserved_enum,
          :reserved_enum2, :lzma_reserved_enum
      end

      attach_function :lzma_auto_decoder, [:pointer, :uint64, :uint32], :lzma_ret
      attach_function :lzma_code, [:pointer, :lzma_action], :lzma_ret
      attach_function :lzma_end, [:pointer], :void
    end

    class Stream
      def initialize(stream, buf_len=4096)
        @stream, @buf_len = stream, buf_len || 4096
        @buf = (' ' * @buf_len).pointer
        @struct = C::LZMAStream.new

        ObjectSpace.define_finalizer(self, method(:finalize))
      end

      def avail_in
        @struct[:avail_in]
      end

      def total_in
        @struct[:total_in]
      end

      def avail_out
        @struct[:avail_out]
      end

      def total_out
        @struct[:total_out]
      end

      def to_ffi
        @struct
      end

      def ptr
        @struct.pointer
      end

      def size
        @struct.size
      end

      def to_s
        %w[in out].flat_map {|i|
          %w[next avail total].map {|w|
            send("#{w}_#{i}".to_sym)
          }
        }
      end

      def decoder(limit=-1, flags=0)
        code = nil
        raise RuntimeError, "lzma_stream_decoder error: #{code}" if (code = C.lzma_auto_decoder(@struct.pointer, limit, flags)) != :OK
        self
      end

      def read
        @struct[:next_in] = FFI::MemoryPointer.from_string(str = @stream.read(@buf_len))
        @struct[:avail_in] = str.bytesize
      end

      def code(action)
        @struct[:next_out] = @buf
        @struct[:avail_out] = @buf_len
        C.lzma_code(@struct.pointer, action)
      end

      def next_out
        @buf.read_string_length(@buf_len - @struct[:avail_out])
      end

      def finalize
        C.lzma_end(@struct.pointer)
      end

      def self.size
        C::LZMAStream.size
      end
    end

    def self.decompress(what, buf_len=4096, &blk)
      what = StringIO.new(what.to_s) unless what.is_a?(IO)
      res = ''
      blk = lambda {|chunk| res << chunk } unless block_given?

      stream = Stream.new(what, buf_len).decoder

      until what.eof?
        stream.read
        action = what.eof? ? :FINISH : :RUN

        begin
          code = nil
          raise RuntimeError, "lzma_code error: #{code}" unless [:OK, :STREAM_END].include?(code = stream.code(action))

          blk.call(stream.next_out)
        end while stream.avail_out.zero?
      end

      stream.finalize
      what.close

      block_given? ? what : res
    end

    def self.extract(file, to=nil, buf_len=4096)
      to ||=file.gsub(/\.(xz|lzma)$/, '')
      File.unlink(to) if File.file?(to)
      File.open(to, 'wb') {|f|
        decompress(File.open(file), buf_len) {|chunk|
          f.write(chunk)
        }
      }

      to
    end
  end
end
