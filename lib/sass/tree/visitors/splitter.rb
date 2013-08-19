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
    node
  end

  def visit_prop(node)
    if (should_include?(node.name, node.value) )
      yield
    else
      []
    end
  end

  def visit_rule(node)
    if (should_include?(node.rule))
      super(node)
    else
      yield
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
    result.imported_file.to_tree
  end

  def visit_mixin(node)
    # all the vars and things will be worked out in what the mixin contains
    res = super(node)
    # It returns us a trace-node always.  And we'd like to avoid putting
    # out bad SCSS with {} {} and such.
    res.children
  end

  def visit_variable(node)
    super(node)
  end

  def should_include?(*node_data)
    node_data = [node_data].flatten.compact
    # if it has things which aren't a string.
    has_dynamic = node_data.select {|t| t.is_a?(::Sass::Script::Variable)}.size > 0

    include_it = (@output == :dynamic) ? has_dynamic : !has_dynamic
    include_it
  end
end
