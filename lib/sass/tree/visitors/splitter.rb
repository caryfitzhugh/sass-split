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
    visit( result.imported_file.to_tree )
  end

  def visit_mixin(node)
    binding.pry
    mixin = @environment.mixin(node.name)
    arguments = [node.args + node.keywords.values].flatten
    contains_dynamic_arguments = has_dynamic_data?(arguments)

    if (@ouput == :dynamic && contains_dynamic_arguments)
      # Copy out with the variables replaced with the included nodes

    elsif (@output == :static && !contains_dynamic_arguments)
      # Copy out with everything resolved.

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

  def has_dynamic_data?(*node_data)
    node_data = [node_data].flatten.compact

    node_data.select do |t|
      if t.is_a?(::Sass::Script::Variable)
        true

      elsif t.is_a?(::Sass::Script::Operation)
        # If it's an operation, look inside and see if it's got dynamic data in there...
        has_dynamic_data?(t.children)

      elsif t.is_a?(::Sass::Script::List)
        # If it's a list, we need to examine it a bit closer...
        has_dynamic_data?(t.value)
      end
    end.size > 0
  end
end
