require 'optparse'
require 'fileutils'

module Sass
  # This module handles the various Sass executables
  module Exec
    # An abstract class that encapsulates the executable code for all three executables.
    class Generic
      # @param args [Array<String>] The command-line arguments
      def initialize(args)
        @args = args
        @options = {}
      end

      # Parses the command-line arguments and runs the executable.
      # Calls `Kernel#exit` at the end, so it never returns.
      #
      # @see #parse
      def parse!
        begin
          parse
        rescue Exception => e
          raise e if @options[:trace] || e.is_a?(SystemExit)

          $stderr.print "#{e.class}: " unless e.class == RuntimeError
          $stderr.puts "#{e.message}"
          $stderr.puts "  Use --trace for backtrace."
          exit 1
        end
        exit 0
      end

      # Parses the command-line arguments and runs the executable.
      # This does not handle exceptions or exit the program.
      #
      # @see #parse!
      def parse
        @opts = OptionParser.new(&method(:set_opts))
        @opts.parse!(@args)

        process_result

        @options
      end

      # @return [String] A description of the executable
      def to_s
        @opts.to_s
      end

      protected

      # Finds the line of the source template
      # on which an exception was raised.
      #
      # @param exception [Exception] The exception
      # @return [String] The line number
      def get_line(exception)
        # SyntaxErrors have weird line reporting
        # when there's trailing whitespace
        return (exception.message.scan(/:(\d+)/).first || ["??"]).first if exception.is_a?(::SyntaxError)
        (exception.backtrace[0].scan(/:(\d+)/).first || ["??"]).first
      end

      # Tells optparse how to parse the arguments
      # available for all executables.
      #
      # This is meant to be overridden by subclasses
      # so they can add their own options.
      #
      # @param opts [OptionParser]
      def set_opts(opts)
        opts.on('-s', '--stdin', :NONE, 'Read input from standard input instead of an input file') do
          @options[:input] = $stdin
        end

        opts.on('--trace', :NONE, 'Show a full traceback on error') do
          @options[:trace] = true
        end

        opts.on('--unix-newlines', 'Use Unix-style newlines in written files.') do
          @options[:unix_newlines] = true if ::Sass::Util.windows?
        end

        opts.on_tail("-?", "-h", "--help", "Show this message") do
          puts opts
          exit
        end

        opts.on_tail("-v", "--version", "Print version") do
          puts("Sass #{::Sass.version[:string]}")
          exit
        end
      end

      # Processes the options set by the command-line arguments.
      # In particular, sets `@options[:input]` and `@options[:output]`
      # to appropriate IO streams.
      #
      # This is meant to be overridden by subclasses
      # so they can run their respective programs.
      def process_result
        input, output = @options[:input], @options[:output]
        args = @args.dup
        input ||=
          begin
            filename = args.shift
            @options[:filename] = filename
            open_file(filename) || $stdin
          end
        output ||= args.shift || $stdout

        @options[:input], @options[:output] = input, output
      end

      COLORS = { :red => 31, :green => 32, :yellow => 33 }

      # Prints a status message about performing the given action,
      # colored using the given color (via terminal escapes) if possible.
      #
      # @param name [#to_s] A short name for the action being performed.
      #   Shouldn't be longer than 11 characters.
      # @param color [Symbol] The name of the color to use for this action.
      #   Can be `:red`, `:green`, or `:yellow`.
      def puts_action(name, color, arg)
        return if @options[:for_engine][:quiet]
        printf color(color, "%11s %s\n"), name, arg
        STDOUT.flush
      end

      # Same as \{Kernel.puts}, but doesn't print anything if the `--quiet` option is set.
      #
      # @param args [Array] Passed on to \{Kernel.puts}
      def puts(*args)
        return if @options[:for_engine][:quiet]
        Kernel.puts(*args)
      end

      # Wraps the given string in terminal escapes
      # causing it to have the given color.
      # If terminal esapes aren't supported on this platform,
      # just returns the string instead.
      #
      # @param color [Symbol] The name of the color to use.
      #   Can be `:red`, `:green`, or `:yellow`.
      # @param str [String] The string to wrap in the given color.
      # @return [String] The wrapped string.
      def color(color, str)
        raise "[BUG] Unrecognized color #{color}" unless COLORS[color]

        # Almost any real Unix terminal will support color,
        # so we just filter for Windows terms (which don't set TERM)
        # and not-real terminals, which aren't ttys.
        return str if ENV["TERM"].nil? || ENV["TERM"].empty? || !STDOUT.tty?
        return "\e[#{COLORS[color]}m#{str}\e[0m"
      end

      def write_output(text, destination)
        if destination.is_a?(String)
          open_file(destination, 'w') {|file| file.write(text)}
        else
          destination.write(text)
        end
      end

      private

      def open_file(filename, flag = 'r')
        return if filename.nil?
        flag = 'wb' if @options[:unix_newlines] && flag == 'w'
        file = File.open(filename, flag)
        return file unless block_given?
        yield file
        file.close
      end

      def handle_load_error(err)
        dep = err.message[/^no such file to load -- (.*)/, 1]
        raise err if @options[:trace] || dep.nil? || dep.empty?
        $stderr.puts <<MESSAGE
Required dependency #{dep} not found!
    Run "gem install #{dep}" to get it.
  Use --trace for backtrace.
MESSAGE
        exit 1
      end
    end

    class SassSplit < Generic
      # @param args [Array<String>] The command-line arguments
      def initialize(args)
        super
        require 'sass'
        @options[:for_tree] = {}
        @options[:extract]  = :static
        @options[:for_engine] = {:cache => false, :read_cache => true, :load_paths => []}
      end

      # Tells optparse how to parse the arguments.
      #
      # @param opts [OptionParser]
      def set_opts(opts)
        opts.banner = <<END
Usage: sass-split [options] [INPUT] [OUTPUT]

Description:
  Splits a Sass/SCSS file into a dynamic and static file.

Options:
END

        opts.on('-d', '--dynamic',
          "Extract the dynamic code to output") do |dyn|
            @options[:extract] = :dynamic
        end

        opts.on('-I', '--load-path PATH', 'Add a sass import path.') do |path|
          @options[:for_engine][:load_paths] << path
        end
        opts.on('-r', '--require LIB', 'Require a Ruby library before running Sass.') do |lib|
          require lib
        end
        opts.on('--cache-location PATH', 'The path to put cached Sass files. Defaults to .sass-cache.') do |loc|
          @options[:for_engine][:cache_location] = loc
        end

        super(opts)
      end

      # Processes the options set by the command-line arguments,
      # and runs the CSS compiler appropriately.
      def process_result
        require 'sass'

        super
        input = @options[:input]
        output = @options[:output]
        process_file(input, output)
      end

      private


      def process_file(input, output)
        if input.is_a?(File)
          @options[:from] ||=
            case input.path
            when /\.scss$/; :scss
            when /\.sass$/; :sass
            end
        end

        if output.is_a?(File)
          @options[:to] ||=
            case output.path
            when /\.scss$/; :scss
            when /\.sass$/; :sass
            end
        end

        @options[:from] ||= :scss
        @options[:to] ||= :scss
        @options[:for_engine][:syntax] = @options[:from]

        output_tree =
          ::Sass::Util.silence_sass_warnings do
            if input.is_a?(File)
              ::Sass::Engine.for_file(input.path, @options[:for_engine])
            else
              ::Sass::Engine.new(input.read, @options[:for_engine])
            end.to_tree
          end

        require 'pp'
        require 'pry'
        require 'sass/tree/visitors/splitter' # Put in engine.rb

        # We want SCSS
        out = ::Sass::Tree::Visitors::Splitter.visit(output_tree, @options[:extract]).to_scss

        output = input.path if @options[:in_place]
        write_output(out, output)
      rescue ::Sass::SyntaxError => e
        raise e if @options[:trace]
        file = " of #{e.sass_filename}" if e.sass_filename
        raise "Error on line #{e.sass_line}#{file}: #{e.message}\n  Use --trace for backtrace"
      rescue LoadError => err
        handle_load_error(err)
      end
      private

      def has_variables?(*inputs)
        [inputs].flatten.select do |n|
          n.is_a?(::Sass::Script::Node)
        end.size > 0
      end

    end
  end
end
