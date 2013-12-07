# A processor for Day One entries to be used in a Jekyll Generator
# plugin.
#
# Author::    Jeff Verkoeyen  (mailto:jverkoey@gmail.com)
# Copyright:: Copyright (c) 2013 Featherless Software Design
# License::   Apache 2.0

# Day One entries are stored in the plist format.
require 'plist'

DAYONE_CONFIG_PATH = File.join(File.dirname(__FILE__), 'config.yml')
TAG_TREE_POST_KEY = '#_post_#'

# The Day One Jekyll module. This module includes a Processor class
# which may be subclassed in order to provide additional
# functionality. When the processor is executed on a given Generator
# page, Day One entries will be made accessible via `page.dayones`.
module Dayone
  class Processor

    # Takes an array of tag strings and returns an array that
    # can be used to walk a tag tree. The resulting array is
    # ordered and each tag is standardized (lowercased,
    # etc...).
    # Params:
    # +tags+:: An Array of Strings.
    # Returns:
    # An Array of Strings, sorted alphabetically and
    # standardized.
    def generate_tag_walk(tags)
      # Note(featherless): Am I missing a cleaner way to
      # bail out for nil args?
      if tags.nil? or not tags.any? then
        return nil
      end

      # Lowercased sort to standardize tag names between
      # Day One and Jekyll. Not doing this would lead to
      # capitalization differences causing Day One posts
      # not to match up to their Jekyll counterparts.
      return tags.map{|tag| tag.downcase.strip}.sort
    end

    # Builds a tag tree from an array of tag strings.
    def build_tag_tree(tag_tree, tags)
      tag_walk = generate_tag_walk(tags)
      if tag_walk.nil? then
        return nil
      end

      node = tag_tree
      tag_walk.each do |tag|
        if not node.has_key?(tag) then
          node[tag] = Hash.new
        end
        node = node[tag]
      end

      return node
    end

    # Walks the tag tree with the given tags and
    # returns an array of posts that were attached
    # to any touched nodes.
    def get_tag_tree_posts(tag_tree, tags)
      tag_walk = generate_tag_walk(tags)
      if tag_walk.nil? then
        return nil
      end

      posts = Array.new

      # Typical breadth-first search using the
      # existence of a branch in the tag_walk to
      # determine whether a node is traversed.

      queue = [tag_tree]

      # Consulted with @thatwasawesome for this efficient algorithm.
      while queue.length > 0
        node = queue.shift

        # We return every touched node's post, if
        # it has one.
        if node.has_key?(TAG_TREE_POST_KEY) then
          posts.push(node[TAG_TREE_POST_KEY])
        end

        tag_walk.each do |tag|
          if node.has_key?(tag) then
            queue.push(node[tag])
          end
        end

      end
      
      return posts
    end
    
    # Recursively walks a hash tree and sanitizes each key
    # so that they can be used in Liquid templates. Spaces
    # will be replaced with "_" characters and all
    # characters will be lowercased.
    #
    # Day One Note:
    # Day One keys tend to have spaces, making it difficult
    # to access certain properties of each dayone entry in
    # Liquid templates.
    #
    # Returns:
    # The sanitized hash.
    def sanitize_keys(hash)
      new_hash = Hash.new
      hash.each do |key,value|
        sanitized_key = key.downcase.tr(" ", "_")

        if value.class == Hash then
          new_hash[sanitized_key] = sanitize_keys(value)
        else
          new_hash[sanitized_key] = value
        end
      end
      return new_hash
    end
    
    # Tests if haystack includes any of the needles.
    def orinclude?(haystack, needles)
      if haystack.nil? or needles.nil? then
        return false
      end

      needles.each do |needle|
        if haystack.include?(needle)
          return true
        end
      end
      return false
    end

    # Returns an enumerator that touches all of the posts
    # in the tag_tree.
    #
    # Modified from http://stackoverflow.com/questions/3748744/traversing-a-hash-recursively-in-ruby
    def post_enumerator_from_tag_tree(tag_tree, &block)
      return enum_for(:post_enumerator_from_tag_tree, tag_tree) unless block

      if not tag_tree[TAG_TREE_POST_KEY].nil?
        yield tag_tree[TAG_TREE_POST_KEY]
      end
      tag_tree.each do |k,v|
        if v.is_a? Hash
          post_enumerator_from_tag_tree(v, &block)
        end
      end
    end
    
    # Extracts the title from a given Day One entry.
    #
    # The title is the first sentence of a Day One entry unless
    # that sentence is part of a paragraph.
    def extract_title(doc)
      entry_text = doc['entry_text'].strip
      title_text = nil

      # Get the title.
      loc_firstperiod = entry_text.index(".")
      loc_firstnewline = entry_text.index("\n")
      if not loc_firstnewline.nil? and not loc_firstperiod.nil? then
        # Newline before the first period or directly after it.
        if loc_firstnewline < loc_firstperiod then
          title_text = entry_text[0, loc_firstnewline]
          entry_text = entry_text[loc_firstnewline + 1..entry_text.length]
        elsif loc_firstperiod == loc_firstnewline - 1 then
          title_text = entry_text[0, loc_firstperiod]
          entry_text = entry_text[loc_firstperiod + 1..entry_text.length]
        end
      elsif not loc_firstnewline.nil? and loc_firstperiod.nil? then  
        title_text = entry_text[0, loc_firstnewline]
        entry_text = entry_text[loc_firstnewline+1..entry_text.length]
      end
      doc['entry_text'] = entry_text
      doc['title_text'] = title_text
    end
    
    # Returns a Boolean indicating whether or not the title should
    # be extracted from the first line of the given Day One entry.
    def should_extract_title(doc)
      return true
    end

    # To be called from your Generator's generate method.
    def attach_dayones_to_site(site)
      # Load the server settings so that we can find the Day One path.
      print "\n       Extracting Day One Posts:"
      serverconfig = YAML::load(File.open(DAYONE_CONFIG_PATH))

      # We have the server config YAML loaded, find the Day One path.
      dayonepath = serverconfig['dayonepath']
      raise "Missing dayonepath key in " + DAYONE_CONFIG_PATH if dayonepath.nil?
      raise "dayonepath must point to an existing path" if not File.directory?(dayonepath)
      
      print "\n          - Building tag tree... "

      # Build the tag tree from Jekyll's posts. We'll use the Day One entry
      # tags to find which post to attach each to later.
      tag_tree = Hash.new
      site.posts.each do |post|
        if not post.tags.any? then
          next
        end

        node = build_tag_tree(tag_tree, post.tags)
        node[TAG_TREE_POST_KEY] = post
      end

      print "\n          - Correlating Day One entries with Jekyll posts... "

      Dir.glob(dayonepath + "/entries/*.doentry") do |dayone_entry|
        doc = Plist::parse_xml(dayone_entry)

        # Cleans the doc by replacing spaces with underscores and lower-casing all key names.
        doc = sanitize_keys(doc)

        doc['has_pic'] = File.exist?(dayonepath + "/photos/" + doc['uuid'] + ".jpg")
        # In order to parse the data in Liquid we have to convert the DateTime object to a string.
        doc['creation_date'] = doc['creation_date'].to_s

        if should_extract_title(doc) then
          extract_title(doc)
        end

        process_entry(doc)

        # Find all of the posts that this Day One's tags match to.
        posts = get_tag_tree_posts(tag_tree, doc['tags'])
        if posts.nil? or posts.length == 0 then
          next
        end
        
        posts.each do |post|
          data = post.data

          # Attach this Day One entry to the post.
          if not data.has_key?('dayones') then
            data['dayones'] = Array.new
          end
          data['dayones'].concat([doc])
        end
      end

      print "\n          - Sorting Day One entries... "
      # Once we've added all Day One entries, we run a final pass to
      # sort them.
      post_enumerator_from_tag_tree(tag_tree).each do |post|
        if post.data.has_key?('dayones') then
          post.data['dayones'].sort! { |a,b| a['creation_date'] <=> b['creation_date'] }
        end

        process_post(post)
      end
      
      print "\n          - Done\n                    "
    end

    # For processing a Jekyll post after all Day One entries
    # have been added and before the post is passed to
    # Liquid.
    def process_post(post)
      # No-op.
    end

    # For processing a Day One entry.
    def process_entry(entry)
      # No-op.
    end

  end
end

# Sample Day One entry
# location: 
#   place_name: Bahia Del Sol Hotel
#   locality: Bocas del Toro
#   administrative_area: Panama
#   longitude: -82.2414207458496
#   latitude: 9.33639517750777
#   foursquare_id: 4c8ffc2f5fdf6dcb9fef2c91
#   country: Panama
# starred: false
# entry_text: |-
#   Bahia del Sol
#   
#   $130
# weather: 
#   pressure_mb: 1007.46
#   description: Partly Cloudy
#   fahrenheit: "80"
#   wind_bearing: 279
#   iconname: cloudyn.png
#   visibility_km: 14.56
#   celsius: "26"
#   relative_humidity: 76.0
#   wind_speed_kph: 9.61
#   service: Forecast.io
# creation_date: 2013-11-16T02:00:00+00:00
# activity: Stationary
# uuid: F094F6DF8F314A99B613C0D552076496
# time_zone: America/Costa_Rica
# tags: 
# - Panama
# - Bocas del Toro
# - Bed and Breakfast
# has_pic: false
# creator: 
#   generation_date: 2013-11-26T17:00:13+00:00
#   host_name: swift
#   software_agent: Day One iOS/1.12
#   os_agent: iOS/7.0.4
#   device_agent: iPhone/iPhone4,1