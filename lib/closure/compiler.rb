require 'stringio'
require 'open3'

module Closure

  # We raise a Closure::Error when compilation fails for any reason.
  class Error < StandardError; end

  # Wrap open3 process with a bit nicer interface
  class ProcessWrapper
    def initialize(command)
      @prompt_read = false
      stdin, stdout, stderr, _ = Open3::popen3(command)
      @in = stdin
      @out = stdout
      @error = stderr
    end

    def write(chunk)
      read_prompt unless prompt_read?
      @in.write(chunk)
    end

    def result
      @in.flush
      @in.close
      readable, _writable, _errored = IO.select([@out, @error])

      if readable && readable.any? { |s| s == @error }
        raise Error, @error.read
      else
        @out.read
      end
    end

    private

    def read_prompt
      @prompt_read = true
      @error.readline
    end

    def prompt_read?
      @prompt_read == true
    end
  end

  # The Closure::Compiler is a basic wrapper around the actual JAR. There's not
  # much to see here.
  class Compiler

    attr_accessor :options

    DEFAULT_OPTIONS = {
      :warning_level => 'QUIET',
      :language_in => 'ECMASCRIPT5'
    }

    JVM_FLAGS = '-XX:TieredStopAtLevel=1'

    # When you create a Compiler, pass in the flags and options.
    def initialize(options={})
      @java     = options.delete(:java)     || JAVA_COMMAND
      @jar      = options.delete(:jar_file) || COMPILER_JAR
      @options  = DEFAULT_OPTIONS.merge(options)
    end

    # Can compile a JavaScript string or open IO object. Returns the compiled
    # JavaScript as a string or yields an IO object containing the response to a
    # block, for streaming.
    def compile(io)
      process = ProcessWrapper.new(command)
      if io.respond_to? :read
        while buffer = io.read(4096) do
          process.write(buffer)
        end
      else
        process.write(io.to_s)
      end

      result = process.result
      yield(StringIO.new(result)) if block_given?
      result
    end
    alias_method :compress, :compile

    # Takes an array of javascript file paths or a single path. Returns the
    # resulting JavaScript as a string or yields an IO object containing the
    # response to a block, for streaming.
    def compile_files(files)
      @options.merge!(:js => files)

      result = ProcessWrapper.new(command).result

      yield(StringIO.new(result)) if block_given?
      result
    end
    alias_method :compile_file, :compile_files

    private

    # Serialize hash options to the command-line format.
    def serialize_options(options)
      options.map do |k, v|
        if (v.is_a?(Array))
          v.map {|v2| ["--#{k}", v2.to_s]}
        else
          ["--#{k}", v.to_s]
        end
      end.flatten
    end

    def command
      [@java, '-jar', JVM_FLAGS, "\"#{@jar}\"", serialize_options(@options)].flatten.join(' ')
    end

  end
end
