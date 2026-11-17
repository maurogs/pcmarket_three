# The tree is built as a plain value first: a `do ... end` block would bind to
# json.categories (jbuilder's block form) and silently emit an empty array.
tree = @categories.map do |root|
  children = root.children.order(:position, :id).map do |child|
    { id: child.id, name: child.name, slug: child.slug, parent_id: root.id }
  end

  { id: root.id, name: root.name, slug: root.slug, parent_id: nil, children: children }
end

json.categories tree
