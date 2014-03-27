motion_require "./base_layout_class_methods"

module MotionKit
  # Abstract base class, responsible for "registration" of layout classes with
  # the class `targets` method.
  #
  # Very few methods are defined on BaseLayout, and any unknown methods are
  # delegated to the 'apply' method, which accepts a method name, arguments, and
  # an optional block to set the new context.
  #
  # The ViewLayout subclass defines methods that are appropriate for adding and
  # removing views to a view hierarchy.
  class BaseLayout
    # Class methods reside in base_layout_class_methods.rb
    extend BaseLayoutClassMethods

    attr :parent

    def initialize
      # @layout is the object we look in for style methods
      @layout = self
      # the Layout object that implements custom style methods. Leave this as nil
      # in the initializer.
      @layout_delegate = nil
      @layout_state = :initial
    end

    def set_layout(layout)
      @layout = layout && WeakRef.new(layout)
    end

    def target
      if @layout.nil? || @layout == self
        # only the "root layout" instance is allowed to change the context.
        # if there isn't a context set, try and create a root instance; this
        # will fail if we're not in a state that allows the root to be created
        @context ||= create_default_root_context
      else
        # child layouts get the context from the root layout
        @layout.target
      end
    end
    def v ; target ; end

    # Runs a block of code with a new object as the 'context'. Methods from the
    # Layout classes are applied to this target object, and missing methods are
    # delegated to a new Layout instance that is created based on the new
    # context.
    #
    # This method is part of the public API, you can pass in any object to have
    # it become the 'context'.
    #
    # Example:
    #     def table_view_style
    #       content = target.contentView
    #       if content
    #         context(content) do
    #           background_color UIColor.clearColor
    #         end
    #       end
    #
    #       # usually you use 'context' automatically via method_missing, by
    #       # passing a block to a method that returns an object. That object becomes
    #       # the new context.
    #       layer do
    #         # self is now a CALayerLayout instance
    #         corner_radius 5
    #       end
    #     end
    def context(target, &block)
      return target unless block
      # this little line is incredibly important; the context is only set on
      # the top-level Layout object.
      return @layout.context(target, &block) if @layout && @layout != self

      context_was, parent_was, delegate_was = @context, @parent, @layout_delegate

      @parent = MK::Parent.new(context_was)
      @context = target
      @context.motion_kit_meta[:delegate] ||= Layout.layout_for(@layout, @context.class)
      @layout_delegate = @context.motion_kit_meta[:delegate]
      yield
      @layout_delegate, @context, @parent = delegate_was, context_was, parent_was

      target
    end

    # All missing methods get delegated to either the @layout_delegate or
    # applied to the context using one of the setter methods that `apply`
    # supports.
    def method_missing(method_name, *args, &block)
      self.apply(method_name, *args, &block)
    end

    # Tries to call the setter (`foo 'value'` => `view.setFoo('value')`), or
    # assignment method (`foo 'value'` => `view.foo = 'value'`), or if a block
    # is given, then the object returned by 'method_name' is assigned as the new
    # context, and the block is executed.
    #
    # You can call this method directly, but usually it is called via
    # method_missing.
    def apply(method_name, *args, &block)
      method_name = method_name.to_s
      raise ApplyError.new("Cannot apply #{method_name.inspect} to instance of #{target.class.name}") if method_name.length == 0

      @layout_delegate ||= Layout.layout_for(@layout, target.class)
      return @layout_delegate.send(method_name, *args, &block) if @layout_delegate.respond_to?(method_name)
      
      if block
        apply_with_context(method_name, *args, &block)
      else
        apply_with_target(method_name, *args, &block)
      end
    end

    def apply_with_context(method_name, *args, &block)
      if target.respondsToSelector(method_name)
        new_context = target.send(method_name, *args)
        self.context(new_context, &block)
      elsif method_name.include?('_')
        objc_name = MotionKit.objective_c_method_name(method_name)
        self.apply(objc_name, *args, &block)
      else
        raise ApplyError.new("Cannot apply #{method_name.inspect} to instance of #{target.class.name}")
      end
    end

    def apply_with_target(method_name, *args, &block)
      setter = "set" + method_name.capitalize + ':'
      assign = method_name + '='
      
      # The order is important here.
      if target.respond_to?(setter)
        target.send(setter, *args)
      elsif target.respond_to?(assign)
        target.send(assign, *args)
      elsif target.respond_to?(method_name)
        target.send(method_name, *args)
      # UIAppearance classes are a whole OTHER thing; they never return 'true'
      elsif target.is_a?(MotionKit.appearance_class)
        target.send(setter, *args)
      # Finally, try again with camel case if there's an underscore.
      elsif method_name.include?('_')
        objc_name = MotionKit.objective_c_method_name(method_name)
        self.apply(objc_name, *args)
      else
        raise ApplyError.new("Cannot apply #{method_name.inspect} to instance of #{target.class.name}")
      end
    end

  public

    # this last little "catch-all" method is helpful to warn against methods
    # that are defined already. Since magic methods are so important, this
    # warning can come in handy.
    def self.method_added(method_name)
      if self < BaseLayout && BaseLayout.method_defined?(method_name)
        NSLog("Warning! The method #{self.name}##{method_name} has already been defined on MotionKit::BaseLayout or one of its ancestors.")
      end
    end

  end

end