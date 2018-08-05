#! /usr/bin/env ruby

require 'nokogiri'

STDOUT.sync = true

require File.join(__dir__, 'image_downloader_common.rb')

#
# Generate data/images.yml file
#
class ImageDownloader
  include ImageDownloaderCommon

  def execute

    data = load_merged_data
    result = {}
    data.each do |word, entries|
      result[word] = []
      entries.each.with_index do |entry, i|
        if entry['ext']
          filename = image_file_name(word, i, entry['ext'])
          image_file = File.join(IMAGES_DIR, filename)
          if File.exist?(image_file)
            generate_thumbnail(filename, false)
            result[word] << Marshal.load(Marshal.dump(entry))
            next
          end
        end
        puts "Update: #{word}"
        new_entry = download_image(word, entry['url'], i)
        next if new_entry.nil?
        new_entry.delete('cache_path')
        result[word] << new_entry
      end
    end

    save_yaml(result)
  end

  def query_api(url)
    if url =~ %r{\Ahttps://pixabay\.com/photo-(\d+)/\z}
      return query_pixabay_api(url, $1)
    elsif url =~ %r{\Ahttps://pixabay\.com/en/.+-(\d+)/\z}
      return query_pixabay_api(url, $1)
    elsif url =~ %r{\Ahttps?://www\.irasutoya\.com/\d{4}/\d{2}/.+\.html(#\d+)?\z}
      return query_irasutoya_api(url)
    elsif url =~ %r{\Ahttps://commons\.wikimedia\.org/wiki/(File:[^&\?/#]+\.(?:jpe?g|png|gif|svg))\z}i
      return query_wikipedia_api(url, $1)
    else
      abort "ERROR: unknown url pattern #{url}"
    end
  end

  def query_pixabay_api(url, id)
    cache_url = "https://pixabay.com/api/?id=#{id}&key="
    real_url = cache_url + ENV['PIXABAY_API_KEY']
    cache_path = save_url('pba-', 'json', real_url, cache_url, true)
    return nil if cache_path.nil?

    data = JSON.parse(File.read(cache_path))
    data = data['hits'][0]
    image_url = data['webformatURL']
    ext = image_url[/\.([a-zA-Z]{2,4})\z/, 1].downcase
    return nil if ext.empty?
    cache_path = save_url('pbi-', ext, image_url, nil, true)
    return nil if cache_path.nil?

    return {
      'url' => url,
      'cache_path' => cache_path,
      'site' => 'pixabay',
      'ext' => ext,
      'original' => image_url,
      'api' => cache_url,
      'credit' => {
        'name' => data['user'],
        'id' => data['user_id']
      },
    }
  end

  def query_irasutoya_api(url)
    img_pos = 0
    page_url = url.sub(/\Ahttp:/, 'https:')
    # cache_url = url.sub(/\Ahttps:/, 'http:')

    if page_url =~ /#(\d+)\z/
      img_pos = $1.to_i - 1
      page_url = page_url.sub(/#(\d+)\z/, '')
    end

    cache_path = save_url('iya-', 'html', page_url)
    doc = Nokogiri::HTML.parse(File.read(cache_path))

    atags = doc.css('.entry').css('a')
    urls = []
    atags.each do |a|
      image_url = a.attr('href')
      image_url = image_url.sub(%r{/s\d+/([^/]+)\z}, '/s640/\1')
      image_url = image_url.sub(%r{\A//}, 'https://')
      urls << image_url
    end
    image_url = urls[img_pos]
    ext = image_url[/\.([a-zA-Z]{2,4})\z/, 1].downcase
    cache_path = save_url('iyi-', ext, image_url) unless ext.empty?

    return {
      'url' => page_url,
      'cache_path' => cache_path,
      'site' => 'irasutoya',
      'ext' => ext,
      'original' => image_url,
      'api' => page_url,
    }
  end

  def query_wikipedia_api(url, title)
    api_url = 'https://commons.wikimedia.org/w/api.php?action=query&format=json'
    api_url += '&prop=imageinfo%7cpageimages&pithumbsize=640&iiprop=extmetadata'
    api_url += '&titles=' + title
    cache_path = save_url('wpa-', 'json', api_url)
    data = JSON.parse(File.read(cache_path))
    data = data['query']['pages'].first[1]
    image_url = data['thumbnail']['source']
    ext = image_url[/\.([a-zA-Z]{2,4})\z/, 1].downcase
    cache_path = save_url('wpi-', ext, image_url) unless ext.empty?

    meta = data['imageinfo'][0]['extmetadata']
    license_name = meta['LicenseShortName']['value'] if meta['LicenseShortName']
    license_url = meta['LicenseUrl']['value'] if meta['LicenseUrl']

    return {
      'url' => url,
      'cache_path' => cache_path,
      'site' => 'wikipedia',
      'ext' => ext,
      'original' => image_url,
      'api' => api_url,
      'license' => {
        'name' => license_name,
        'url' => license_url,
      }
    }
  end
end

ImageDownloader.new.execute
