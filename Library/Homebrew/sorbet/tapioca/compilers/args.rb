# typed: strict
# frozen_string_literal: true

require_relative "../../../global"
require "cli/parser"

module Tapioca
  module Compilers
    class Args < Tapioca::Dsl::Compiler
      GLOBAL_OPTIONS = T.let(
        Homebrew::CLI::Parser.global_options.map { _1.slice(0, 2) }.flatten
             .map { "#{Homebrew::CLI::Parser.option_to_name(_1)}?" }.freeze,
        T::Array[String],
      )

      # This is ugly, but we're moving to a new interface that will use a consistent DSL
      # These are cmd/dev-cmd methods that end in `_args` but are not parsers
      NON_PARSER_ARGS_METHODS = T.let([
        :formulae_all_installs_from_args,
        :reproducible_gnutar_args,
        :tar_args,
      ].freeze, T::Array[Symbol])

      # FIXME: Enable cop again when https://github.com/sorbet/sorbet/issues/3532 is fixed.
      # rubocop:disable Style/MutableConstant
      Parsable = T.type_alias { T.any(T.class_of(Homebrew::CLI::Args), T.class_of(Homebrew::AbstractCommand)) }
      ConstantType = type_member { { fixed: Parsable } }
      # rubocop:enable Style/MutableConstant

      sig { override.returns(T::Enumerable[Parsable]) }
      def self.gather_constants
        # require all the commands to ensure the _arg methods are defined
        ["cmd", "dev-cmd"].each do |dir|
          Dir[File.join(__dir__, "../../../#{dir}", "*.rb")].each { require(_1) }
        end
        [Homebrew::CLI::Args] + Homebrew::AbstractCommand.subclasses
      end

      sig { override.void }
      def decorate
        if constant == Homebrew::CLI::Args
          root.create_path(Homebrew::CLI::Args) do |klass|
            Homebrew.methods(false).select { _1.end_with?("_args") }.each do |args_method_name|
              next if NON_PARSER_ARGS_METHODS.include?(args_method_name)

              parser = Homebrew.method(args_method_name).call
              create_args_methods(klass, parser)
            end
          end
        else
          root.create_path(Homebrew::CLI::Args) do |klass|
            create_args_methods(klass, T.must(T.cast(constant, T.class_of(Homebrew::AbstractCommand)).parser))
          end
        end
      end

      sig { params(parser: Homebrew::CLI::Parser).returns(T::Hash[Symbol, T.untyped]) }
      def args_table(parser)
        # we exclude non-args from the table, such as :named and :remaining
        parser.instance_variable_get(:@args).instance_variable_get(:@table).except(:named, :remaining)
      end

      sig { params(parser: Homebrew::CLI::Parser).returns(T::Array[Symbol]) }
      def comma_arrays(parser)
        parser.instance_variable_get(:@non_global_processed_options)
              .filter_map { |k, v| parser.option_to_name(k).to_sym if v == :comma_array }
      end

      sig { params(method_name: Symbol, value: T.untyped, comma_array_methods: T::Array[Symbol]).returns(String) }
      def get_return_type(method_name, value, comma_array_methods)
        if comma_array_methods.include?(method_name)
          "T.nilable(T::Array[String])"
        elsif [true, false].include?(value)
          "T::Boolean"
        else
          "T.nilable(String)"
        end
      end

      private

      sig { params(klass: RBI::Scope, parser: Homebrew::CLI::Parser).void }
      def create_args_methods(klass, parser)
        comma_array_methods = comma_arrays(parser)
        args_table(parser).each do |method_name, value|
          method_name_str = method_name.to_s
          next if GLOBAL_OPTIONS.include?(method_name_str)
          # some args are used in multiple commands (this is ok as long as they have the same type)
          next if klass.nodes.any? { T.cast(_1, RBI::Method).name == method_name_str }

          return_type = get_return_type(method_name, value, comma_array_methods)
          klass.create_method(method_name_str, return_type:)
        end
      end
    end
  end
end
