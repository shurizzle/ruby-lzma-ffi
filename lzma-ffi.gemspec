Gem::Specification.new {|g|
    g.name          = 'lzma-ffi'
    g.version       = '0.0.1'
    g.author        = 'shura'
    g.email         = 'shura1991@gmail.com'
    g.homepage      = 'http://github.com/shurizzle/ruby-lzma-ffi'
    g.platform      = Gem::Platform::RUBY
    g.description   = 'liblzma bindings for ruby'
    g.summary       = g.description
    g.files         = Dir.glob('lib/**/*')
    g.require_path  = 'lib'
    g.executables   = []

    g.add_dependency('ffi')
}
