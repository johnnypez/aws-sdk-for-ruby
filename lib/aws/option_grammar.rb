# Copyright 2011 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

require 'aws/inflection'
require 'aws/meta_utils'
require 'aws/http/request_param'
require 'base64'
require 'set'

module AWS

  # @private
  class OptionGrammar

    # @private
    class DefaultOption; end

    # @private
    class FormatError < ArgumentError
      attr_accessor :expectation
      attr_accessor :context_description

      def initialize(expectation, context)
        @expectation = expectation
        @context_description = context
      end

      def to_s
        "expected #{expectation} for #{context_description}"
      end
    end

    # @private
    module Descriptors

      # @private
      module NoArgs
        def apply(option)
          option.extend self
        end
      end

      module Timestamp

        extend NoArgs

        def validate(value, context = nil)
          true
#             raise format_error("timestamp value", context) unless
#               case value
#               when String 
#                 value =~ /^\d+$/ or value =~ /^\d{4}-\d{2}-d{2}T\d{2}:\d{2}:\d{2}Z$/
#               when String then value =~ /^2009-12-04T20:56:05.000Z\d+$/
#               when Integer then true
#               when DateTime then true
#               when Timestamp then true
#               when Date then true
#               else false
#               end
#             end
#               value.respond_to? :to_str
        end

        def encode_value(value)
          value.to_s
#             value.to_s
#             case value
#             when Integer
#             when 
#             case value
#             when nil, ''  then nil
#             when DateTime then raw
#             when Integer  then DateTime.parse(Time.at(raw).to_s) # timestamp
#             else DateTime.parse(raw.to_s) # work with Time, Date and String objects
#             end
        end
      end

      # @private
      module String

        extend NoArgs

        def validate(value, context = nil)
          raise format_error("string value", context) unless
            value.respond_to? :to_str
        end

        def encode_value(value)
          value.to_s
        end

      end

      # @private
      module Blob

        extend NoArgs

        def validate(value, context = nil)
          raise format_error("string value", context) unless
            value.respond_to? :to_str
        end

        def encode_value(value)
          Base64.encode64(value.to_s)
        end

      end

      # @private
      module Integer

        extend NoArgs

        def validate(value, context = nil)
          raise format_error("integer value", context) unless
            value.respond_to? :to_int
        end

        def encode_value(value)
          value.to_s
        end

      end

      # @private
      module Boolean

        extend NoArgs

        def validate(value, context = nil)
          raise format_error("boolean value", context) unless
            value == true || value == false
        end

        def encode_value(value)
          value.to_s
        end

      end

      # @private
      module Required
        extend NoArgs
        def required?; true; end
      end

      # @private
      module Rename
        def self.apply(option, new_name)
          new_name = Inflection.ruby_name(new_name)
          MetaUtils.extend_method(option, :ruby_name) { new_name }
        end
      end

      # @private
      module Pattern

#         def validate value, context = nil
#           unless value =~ regex
#             raise format_error("value to match #{regex}", context)
#           end
#         end
#       
#         def self.apply option, regex
#           option.extend(self)
#           MetaUtils.extend_method(option, :regex) { regex }
#         end

        def self.apply *args
        end

      end

      # @private
      module ListMethods

        module ClassMethods

          def apply(option, member_descriptors)
            super(option)
            member_option = option.member_option if option.respond_to?(:member_option)
            member_option ||= ListMember.new
            member_option = member_option.extend_with_config(*member_descriptors)
            MetaUtils.extend_method(option, :member_option) { member_option }
          end

        end

        module InstanceMethods

          def validate(value, context = nil)
            raise format_error("enumerable value", context) unless
              value.respond_to? :each
            i = 0
            value.each do |member|
              i += 1
              member_option.validate(member,
                                     "member #{i} of #{context_description(context)}")
            end
          end

          def request_params(value, prefix = nil)
            params = []
            value.each do |v|
              name = prefixed_name(prefix) + join + (params.size + 1).to_s
              params << member_option.request_params(v, name)
            end
            return [Http::Request::Param.new(prefixed_name(prefix), "")] if params.empty?
            params
          end

          def join
            '.'
          end

        end

      end

      module List

        extend NoArgs
        extend ListMethods::ClassMethods
        include ListMethods::InstanceMethods

      end

      module MemberedList

        extend NoArgs
        extend ListMethods::ClassMethods
        include ListMethods::InstanceMethods

        def join
          '.member.'
        end

      end

      class ListMember < DefaultOption

        def initialize options = {}
          super("##list-member##")
          @prefix = options[:prefix] || ''
        end

        def prefixed_name(prefix)
          "#{prefix}#{@prefix}"
        end

      end

      # @private
      module Structure

        extend NoArgs

        def self.apply(option, members)
          options = {}
          options = option.member_options.inject({}) do |memo, member_option|
            memo[member_option.name] = member_option
            memo
          end if option.respond_to?(:member_options)

          super(option)

          members.each do |(name, descriptors)|
            member_option = options[name] || DefaultOption.new(name)
            member_option = member_option.extend_with_config(*descriptors)
            options[name] = member_option
          end

          MetaUtils.extend_method(option, :member_options) { options.values }
          by_ruby_name = options.values.inject({}) do |memo, member_option|
            memo[member_option.ruby_name] = member_option
            memo
          end
          MetaUtils.extend_method(option, :member_option) { |n| by_ruby_name[n] }
        end

        def validate(value, context = nil)
          raise format_error("hash value", context) unless
            value.respond_to?(:to_hash)

          context = context_description(context)

          value.each do |name, v|
            name = name.to_s
            raise ArgumentError.new("unexpected key #{name} for #{context}") unless
              member_option(name)
            member_option(name).validate(v, "key #{name} of #{context}")
          end

          member_options.each do |option|
            raise ArgumentError.new("missing required key #{option.ruby_name} for #{context}") if
              option.required? and
              !value.has_key?(option.ruby_name) and
              !value.has_key?(option.ruby_name.to_sym)
          end
        end

        def request_params(values, prefix = nil)
          values.map do |name, value|
            name = name.to_s
            member_option(name).request_params(value, prefixed_name(prefix))
          end.flatten
        end

      end

      # @private
      module Boolean
        extend NoArgs
      end

    end

    class DefaultOption

      attr_reader :name

      def initialize(name)
        @name = name
      end

      def ruby_name
        Inflection.ruby_name(name)
      end

      def request_params(value, prefix = nil)
        [Http::Request::Param.new(prefixed_name(prefix), encode_value(value))]
      end

      def prefixed_name(prefix)
        return "#{prefix}.#{name}" if prefix
        name
      end

      def encode_value(value)
        value
      end

      def required?
        false
      end

      def format_error(expected, context = nil)
        context = context_description(context)
        FormatError.new(expected, context)
      end

      def context_description(context)
        context or "option #{ruby_name}"
      end

      def extend_with_config(*descriptors)
        option = clone
        descriptors.each do |desc|
          if desc.kind_of?(Hash)
            (name, arg) = desc.to_a.first
          else
            name = desc
            arg = nil
          end
          class_name = Inflection.class_name(name.to_s)
          mod = Descriptors::const_get(class_name)
          if arg
            mod.apply(option, arg)
          else
            mod.apply(option)
          end
        end
        option
      end

      include Descriptors::String

    end

    # @private
    module ModuleMethods

      include Inflection

      def customize(config = [])
        m = Class.new(self)
        supported_options = m.supported_options.inject({}) do |memo, opt|
          memo[opt.name] = opt
          memo
        end
        config.each do |option_config|
          if config.kind_of?(Hash)
            (name, value_desc) = option_config
          else
            (name, value_desc) = parse_option(option_config)
          end
          option = supported_options[name] || DefaultOption.new(name)
          option = option.extend_with_config(*value_desc)
          supported_options[option.name] = option
        end

        supported_ary = supported_options.values
        MetaUtils.extend_method(m, :supported_options) { supported_ary }
        supported_ruby_names = supported_ary.inject({}) do |memo, opt|
          memo[opt.ruby_name] = opt
          memo
        end
        MetaUtils.extend_method(m, :option) { |n| supported_ruby_names[n] }
        supported_ary.each do |opt|
          MetaUtils.extend_method(m, "validate_#{opt.ruby_name}") do |value|
            opt.validate(value)
          end
        end

        m
      end

      def option(name)
        nil
      end

      def supported_options
        []
      end

      def validate(options)
        options.each do |name, value|
          name = name.to_s
          raise ArgumentError.new("unexpected option #{name}") unless
            option(name)
          option(name).validate(value)
        end
        supported_options.each do |option|
          raise ArgumentError.new("missing required option #{option.ruby_name}") unless
            !option.required? ||
            options.has_key?(option.ruby_name) || options.has_key?(option.ruby_name.to_sym)
        end
      end

      def request_params(options)
        validate(options)
        options.map do |(name, value)|
          name = name.to_s
          option(name).request_params(value)
        end.flatten
      end

      def included(m)
        m.extend(self::ModuleMethods)
      end

      protected
      def parse_option(option)
        value_desc = nil
        if option.kind_of? Hash
          raise ArgumentError.new("passed empty hash where an option was expected") if
            option.empty?

          raise ArgumentError.new("too many entries in option description") if
            option.size > 1

          (name, value_desc) = option.to_a.first
          name = name.to_s

          raise ArgumentError.new("expected an array for "+
                                  "value description of option #{name},"+
                                  "got #{value_desc.inspect}") unless
            value_desc.nil? or value_desc.kind_of?(Array)
        else
          name = option
        end

        value_desc ||= []

        [name, value_desc]
      end

      protected
      def apply_required_descriptor(m, name)
        name = ruby_name(name)
        MetaUtils.extend_method(m, :validate) do |opts|
          raise ArgumentError.new("missing required option #{name}") unless
            opts.key? name or opts.key? name.to_sym
        end
      end

      protected
      def apply_integer_descriptor(m, name)
        MetaUtils.extend_method(m, "validate_#{ruby_name(name)}") do |value|
          raise ArgumentError.new("expected integer value for option #{ruby_name(name)}") unless
            value.respond_to? :to_int
        end
      end

      protected
      def apply_string_descriptor(m, name)
        MetaUtils.extend_method(m, "validate_#{ruby_name(name)}") do |value|
          raise ArgumentError.new("expected string value for option #{ruby_name(name)}") unless
            value.respond_to? :to_str
        end
      end

      protected
      def apply_list_descriptor(m, name, arg)
        MetaUtils.extend_method(m, "validate_#{ruby_name(name)}") do |value|
          raise ArgumentError.new("expected value for option #{ruby_name(name)} "+
                                  "to respond to #each") unless
            value.respond_to? :each
        end
        MetaUtils.extend_method(m, "params_for_#{ruby_name(name)}") do |value|
          i = 0
          values = []
          value.each do |member|
            i += 1
            values << Http::Request::Param.new(name+"."+i.to_s, member.to_s)
          end
          if i > 0
            values
          else
            Http::Request::Param.new(name, "")
          end
        end
      end

      protected
      def apply_rename_descriptor(m, name, new_name)
        name = ruby_name(name)
        MetaUtils.extend_method(m, :validate) do |opts|
          raise ArgumentError.new("unexpected option foo") if
            opts.key?(name) or opts.key?(name.to_sym)

          opts = opts.dup
          opts[name] = opts[new_name] if opts.key?(new_name)
          opts[name.to_sym] = opts[new_name.to_sym] if opts.key?(new_name.to_sym)
          opts.delete(new_name)
          opts.delete(new_name.to_sym)
          super(opts)
        end

        # couldn't find a better way to alias a class method
        method = m.method("params_for_#{name}")
        MetaUtils.extend_method(m, "params_for_#{new_name}") do |value|
          method.call(value)
        end
      end

    end

    extend ModuleMethods

  end

end
