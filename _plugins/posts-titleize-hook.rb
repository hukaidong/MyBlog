require 'pry'
require 'active_support/inflector'

Jekyll::Hooks.register :posts, :pre_render do |post|
  post.data['title'] = post.data['title'].titleize(keep_id_suffix: true)
end
