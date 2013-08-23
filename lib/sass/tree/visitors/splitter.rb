# A visitor for converting a Sass tree into SCSS which has only the dynamic / compiled parts present
class Sass::Tree::Visitors::Splitter < Sass::Tree::Visitors::Perform
  # @param root [Tree::Node] The root node of the tree to visit.
  # @param environment [Sass::Environment] The lexical environment.
  # @return [Tree::Node] The resulting tree of static nodes.
  def self.visit(root, output = :dynamic, environment = Sass::Environment.new)
    new(environment, output).send(:visit, root)
  end

  protected
  def initialize(env, output = :dynamic)
    @environment = env
    @output      = output
    # Stack trace information, including mixin includes and imports.
    @stack = []
  end

  def visit(node)
    super
  rescue Sass::SyntaxError => e
    e.modify_backtrace(:filename => node.filename, :line => node.line)
    raise e
  end

  def visit_media(node)
    output = ::Sass::Tree::Visitors::Perform.visit(node, @environment)

    # Now all of the tree is resolved... not what we want.
    # We only want the top level media rule resolved.
    # So only resolve queries
    res = resolve_child_tree(output, [:resolved_query])
    children = node.children.map {|c| visit(c) }
    res.children = children
    res
  end

  def visit_comment(node)
    # We don't want no comments here!
    []
  end

  def visit_prop(node)
    if (should_include?(node.name, node.value) )
      yield
    else
      []
    end
  end

  def visit_rule(node)
    rule_node = if (should_include?(node.rule))

        super(node)
      else
        yield
      end

    # If it's empty, just drop it!
    if rule_node.children.size == 0
      []
    else
      rule_node
    end
  end

  def visit_extend(node)
    if (should_include?(node.selector))
      parser = Sass::SCSS::StaticParser.new(run_interp(node.selector), node.filename, node.line)
      node.resolved_selector = parser.parse_selector
      node
    else
      []
    end
  end

  def visit_import(node)
    result = super(node)
    input = visit( result.imported_file.to_tree )
    input
  end

  def visit_mixin(node)
    # There is a node and a mixin to be considered.
    #
    # The mixin is like the template -- it consists of the nodes which should be added
    # to the tree at this current point
    mixin = @environment.mixin(node.name)

    # The arguments to the mixin are the ones which are passed into the mixin
    arguments = [node.args + node.keywords.values].flatten

    # When considering if a mixing can be expanded, we need to determine if
    # the arguments are dynamic.  If they are, it's all dynamic.
    # If the arguments are static - the mixin *may* be expandable -
    # if the only values inside it are the ones that are filled in by the arguments.
    arguments_are_dynamic = has_dynamic_data?(arguments)

    # We collect a list of all the dynamic data in the mixin tree
    variables_in_tree = recursive_get_dynamic_data(mixin.tree.flatten)
    # And we map the mixin args to mixin local vars (some tricky stuff with splats)
    mixin_args_map    = map_mixin_args(mixin, node.args, node.keywords, node.splat)

    # Examine this map, and delete anything which has a dynamic value
    static_mixin_args_map = mixin_args_map.reject {|k,v| has_dynamic_data?(v) }

    unbound_variables = (variables_in_tree.map(&:name)) - (static_mixin_args_map.keys.map(&:name))

    if (@output == :dynamic)
      if unbound_variables.size > 0
        # Just don't touch it - there's variabilities in there!
        node
      else
        []
      end

    elsif (@output == :static)
      if unbound_variables.size == 0
        output = ::Sass::Tree::Visitors::Perform.visit(node, @environment)

        # What that does is do the standard resolution between the variables and the mixin, etc.
        # We want to 'export' back to scss the value as the resolved value
        # So we need to copy the 'resolved' values to the 'values'.

        output = resolve_child_tree(output)
      else
        []
      end
    end
  end

  def visit_variable(node)
    super(node)
  end

  def should_include?(*node_data)
    node_data = [node_data].flatten.compact

    # if it has things which aren't a string.
    has_dynamic = has_dynamic_data?(node_data)
    include_it = (@output == :dynamic) ? has_dynamic : !has_dynamic
    include_it
  end

  def recursive_get_dynamic_data(nodes)
    evals = ["name", "value", "rule", "args", "arguments", "keywords.values"]

    nodes = [nodes].flatten
    nodes.map do |the_node|

      nodes_data = evals.map do |evl|
        eval "the_node.#{evl}" rescue nil
      end.flatten.compact

     child_nodes = []
     child_nodes = (the_node.respond_to?(:children) && the_node.children) ||
                (the_node.respond_to?(:tree)     && the_node.tree) ||
                []
     child_data = child_nodes.flatten.compact.map  do |child|
         recursive_get_dynamic_data(child)
       end

      descendant_data = (nodes_data + child_data)
      get_dynamic_data(descendant_data)
    end.flatten.compact
  end

  def get_dynamic_data(*node_data)
    node_data = [node_data].flatten.compact

    node_data.map do |t|
      if t.is_a?(::Sass::Script::Variable)
        t

      elsif t.is_a?(::Sass::Script::Operation)
        # If it's an operation, look inside and see if it's got dynamic data in there...
        get_dynamic_data(t.children)

      elsif t.is_a?(::Sass::Script::Funcall)
         get_dynamic_data(t.children)

      elsif t.is_a?(::Sass::Script::List)
        # If it's a list, we need to examine it a bit closer...
        get_dynamic_data(t.value)
      else
        nil
      end
    end.flatten.compact
  end

  def has_dynamic_data?(*node_data)
    get_dynamic_data(node_data).size > 0
  end

  def allow_dynamic_code(&block)
    saved = @ouptut
    @output = :dynamic
    res =  block.call
    @output = saved
    res
  end

  def expand_all_children_etc(child)
    children = [child].flatten
    next_children = children.map do |child|
      if child.respond_to?(:children)
        child.children
      elsif child.respond_to?(:tree)
        child.tree
      else
        child
      end
    end.flatten

    (children + next_children.map do |child_child|
      expand_all_children_etc(child_child)
    end).flatten
  end

  def map_mixin_args(callable, args, keywords, splat)
    args_map = {}

    desc = "#{callable.type.capitalize} #{callable.name}"
    downcase_desc = "#{callable.type} #{callable.name}"

    begin
      unless keywords.empty?
        unknown_args = Sass::Util.array_minus(keywords.keys,
          callable.args.map {|var| var.first.underscored_name})
        if callable.splat && unknown_args.include?(callable.splat.underscored_name)
          raise Sass::SyntaxError.new("Argument $#{callable.splat.name} of #{downcase_desc} cannot be used as a named argument.")
        elsif unknown_args.any?
          description = unknown_args.length > 1 ? 'the following arguments:' : 'an argument named'
          raise Sass::SyntaxError.new("#{desc} doesn't have #{description} #{unknown_args.map {|name| "$#{name}"}.join ', '}.")
        end
      end
    rescue Sass::SyntaxError => keyword_exception
    end

    # If there's no splat, raise the keyword exception immediately. The actual
    # raising happens in the ensure clause at the end of this function.
    return if keyword_exception && !callable.splat

    if args.size > callable.args.size && !callable.splat
      takes = callable.args.size
      passed = args.size
      raise Sass::SyntaxError.new(
        "#{desc} takes #{takes} argument#{'s' unless takes == 1} " +
        "but #{passed} #{passed == 1 ? 'was' : 'were'} passed.")
    end

    splat_sep = :comma
    if splat
      args += splat.to_a
      splat_sep = splat.separator if splat.is_a?(Sass::Script::List)
      # If the splat argument exists, there won't be any keywords passed in
      # manually, so we can safely overwrite rather than merge here.
      keywords = splat.keywords if splat.is_a?(Sass::Script::ArgList)
    end

    keywords = keywords.dup
    env = Sass::Environment.new(callable.environment)
    callable.args.zip(args[0...callable.args.length]) do |(var, default), value|
      if value && keywords.include?(var.underscored_name)
        raise Sass::SyntaxError.new("#{desc} was passed argument $#{var.name} both by position and by name.")
      end

      value ||= keywords.delete(var.underscored_name)
      value ||= default && default.perform(env)
      raise Sass::SyntaxError.new("#{desc} is missing argument #{var.inspect}.") unless value
      args_map[var] = value
    end

    if callable.splat
      rest = args[callable.args.length..-1]
      arg_list = Sass::Script::ArgList.new(rest, keywords.dup, splat_sep)
      arg_list.options = env.options
      args_map[var] = value
    end
    args_map

  rescue Exception => e
  ensure
    # If there's a keyword exception, we don't want to throw it immediately,
    # because the invalid keywords may be part of a glob argument that should be
    # passed on to another function. So we only raise it if we reach the end of
    # this function *and* the keywords attached to the argument list glob object
    # haven't been accessed.
    #
    # The keyword exception takes precedence over any Sass errors, but not over
    # non-Sass exceptions.
    if keyword_exception &&
        !(arg_list && arg_list.keywords_accessed) &&
        (e.nil? || e.is_a?(Sass::SyntaxError))
      raise keyword_exception
    elsif e
      raise e
    end
  end

  def resolve_child_tree(output, what_to_resolve = [:resolved_query, :resolved_name, :resolved_value])
    # For all the children, replace the value with resolved_value
    children = expand_all_children_etc(output).map do |child|
        if child.respond_to?(:resolved_query) && what_to_resolve.include?(:resolved_query)
          child.query = child.resolved_query.to_a
        end

        if child.respond_to?(:resolved_name) && what_to_resolve.include?(:resolved_name)
          child.name = [child.resolved_name]
        end

        if child.respond_to?(:resolved_value) && what_to_resolve.include?(:resolved_value)
          child.value= ::Sass::Script::String.new(child.resolved_value)
        end
        child
      end.flatten
    output
  end
end
