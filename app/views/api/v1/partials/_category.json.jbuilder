json.id category.id
json.name category.name
json.slug category.slug
json.parent_id category.parent_id
# Built outside json.specs: a `do ... end` block binds to json.specs and would
# emit empty child objects instead of these hashes.
specs = category.all_spec_attributes.map do |attribute|
  {
    key: attribute.key,
    label: attribute.name,
    unit: attribute.unit,
    input_type: attribute.input_type,
    filterable: attribute.filterable
  }
end

json.specs specs
