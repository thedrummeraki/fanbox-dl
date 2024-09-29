require 'fileutils'
require 'json'
require 'thread'
require 'debug'

FANBOX_API_URL = 'https://api.fanbox.cc'.freeze
SEPARATOR = ('-' * 100).freeze

def sanitize_filename(filename)
  filename.gsub(/[\s&?*:|"<>()]+/, '_')
end

# A pixiv artist, fetched from the list of supporting artists.
class Artist
  attr_accessor :name, :title, :fee, :id, :creator_id

  class << self
    def from(dict)
      artist = Artist.new
      artist.name = dict['user']['name']
      artist.id = dict['id']
      artist.fee = dict['fee']
      artist.title = dict['title']
      artist.creator_id = dict['creatorId']

      artist
    end
  end

  def skip?
    skipped = Artist.skipped_artists
    [name, title, id, creator_id].select { |x| skipped.include?(x) }.any?
  end

  def self.skipped_artists
    File.readlines('./artist.skip').map { |x| x.strip }
  rescue Errno::ENOENT
    []
  end

  # File system identifier. Used to identify an artist on the file system.
  def fs_identifier
    name
  end
end

# A pixiv fanbox post. Fetched from a list of posts.
class Post
  attr_accessor :id, :title, :fee_required

  def self.from(dict)
    post = Post.new
    post.id = dict['id']
    post.title = dict['title']
    post.fee_required = dict['feeRequired']

    post
  end
end

# A pixiv fanbox file. Can be an image or an attachment.
class FileSpec
  attr_accessor :name, :extension, :url, :post

  def self.from(body, dict, post, index)
    file_spec = FileSpec.new

    position = index + 1
    index_str = position < 10 ? "0#{position}" : position.to_s
    name_parts = [index_str, dict['publishedDatetime']]
    name_parts << body['name'] ? body['name'] : dict['title']
    file_spec.name = name_parts.reject { |x| !x || x.strip.empty? }.join('-')
    file_spec.extension = body['extension']
    file_spec.url = body['originalUrl'] || body['url']
    file_spec.post = post
    file_spec
  end

  def filename
    sanitize_filename("./out/#{post.artist.fs_identifier}/#{post.id}-#{post.title}/#{name}.#{extension}")
  end
end

# A pixiv fanbox's post details. Fetched from a single post.
class PostInfo
  attr_accessor :id, :title, :tags, :excerpt, :images, :files, :artist

  def self.from(dict, artist)
    post_info = PostInfo.new

    body = dict['body']
    post_info.artist = artist
    post_info.id = dict['id']
    post_info.title = dict['title']
    post_info.tags = dict['tags']
    post_info.excerpt = dict['excerpt'] || body['text']

    if body['fileMap']
      post_info.files = body['fileMap'].values.map.with_index do |x, i|
        FileSpec.from(x, dict, post_info, i)
      end
    end
    post_info.files = body['files'].map.with_index { |x, i| FileSpec.from(x, dict, post_info, i) } if body['files']
    if body['imageMap']
      post_info.images = body['imageMap'].values.map.with_index do |x, i|
        FileSpec.from(x, dict, post_info, i)
      end
    end
    post_info.images = body['images'].map.with_index { |x, i| FileSpec.from(x, dict, post_info, i) } if body['images']

    post_info.files = [] unless post_info.files
    post_info.images = [] unless post_info.images

    post_info
  end
end

# GET request, specify where to output the result if applicable.
def get(path, download)
  if download
    print "\t-> #{download}..."
    if File.exist?(download)
      puts ' [skipping -- already exists]'
      return
    else
      puts
    end
  end

  url = path.start_with?('http') ? path : "#{FANBOX_API_URL}#{path}"
  command = "curl -s '#{url}' --compressed -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:130.0) Gecko/20100101 Firefox/130.0' -H 'Accept: application/json, text/plain, */*' -H 'Accept-Language: en-CA,en-US;q=0.7,en;q=0.3' -H 'Accept-Encoding: gzip, deflate, br, zstd' -H 'Origin: https://www.fanbox.cc' -H 'Alt-Used: api.fanbox.cc' -H 'Connection: keep-alive' -H 'Referer: https://www.fanbox.cc/' -H 'Cookie: FANBOXSESSID=44834125_TgaQ3AsiGvM0gpgkQbvUJy61cYblUUV2; p_ab_id=3; p_ab_id_2=8; p_ab_d_id=1089934541; _ga_D9TLP3EFER=GS1.1.1727540900.5.0.1727540900.60.0.0; _ga=GA1.2.1890423635.1727527375; _gcl_au=1.1.925753722.1727527376; _gid=GA1.2.60127567.1727527378; privacy_policy_agreement=7; privacy_policy_notification=0; cf_clearance=kAiwLfaCdqsdET5Td4P7QwntBHq7RX515y3byxhA0jU-1727539058-1.2.1.1-oFeUdxQKSoAShTPMG2jZt.3jYOLx.BA4K7jGdgZd.dDkkrRmWuKaGBVgB49fTZYyk7ZJ52GY9EmR3XTwJR2gh3X4Q_tPqeDdANj10QekfCpkMzG6ONxjNNp9GzrSCByG.QiIpDuPxBoyKD0ztK9k4wIKqVw40YVDRlyNxWFnSlPCXqLeBAq62pqRGGCjqsR6Fs66eJ19J1FaB6oxZgVBXhbhawQRNs.c2zAIneo6aqpPeaZ6fySa4QOuZPqZRdCT9jR9fugIZxi0T5J0zbD9OJtYpPgPRnsJ5Wdzp5GQMYzqlHG3.wEml3qT03L0wrZbYUcHhGGWDVA8WsWA8NvJlnzK9I6Mg7hdNDpYowvuIEw; __cf_bm=a0WxsiAWzD_wI5qUMiIpImZTP1sP.ibmbeHJzMwYHjI-1727540900-1.0.1.1-gieQaIIciqk5Pye7iKf1oKp_YW6Sc7D0ew_20LmMrT55hKRa4mUeIrE6u39PCe8xqY5gYpMAyxUaDiQivAwqEw' -H 'Sec-Fetch-Dest: empty' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: same-site' -H 'TE: trailers'"
  command << " --output - > #{download}" if download
  puts("[GET] #{url}") if !download || ENV['VERBOSE']
  execute(command)
end

# Fanbox specific GET request, returns a parsed JSON (if download is not specified.)
def fanbox(path, download: nil)
  response = get(path, download)
  return if download

  JSON.parse(response)['body']
end

# Execute a shell command.
def execute(cmd)
  puts(cmd) if ENV.fetch('VERBOSE', nil)
  `#{cmd}`
end

# Fetch posts from a specific artist. Must be supporting said artist.
def fetch_artist_posts(artist)
  puts("Fetching posts from '#{artist.name}'...")
  page_urls = fanbox("/post.paginateCreator?creatorId=#{artist.creator_id}")
  posts = page_urls.flat_map { |page_url| fetch_relevant_posts(page_url, artist) }
  puts "Found #{posts.size}"

  # Create a queue to hold the posts
  queue = Queue.new
  posts.each { |post| queue << post }

  # Create a thread pool with a maximum of 5 threads
  threads = []
  5.times do
    threads << Thread.new do
      until queue.empty?
        post = begin
          queue.pop(true)
        rescue StandardError
          nil
        end
        download_post(post, artist) if post
      end
    end
  end

  # Wait for all threads to finish
  threads.each(&:join)
  puts
end

# Fetch paid posts from an artist that are in the supported plan (ie: ignore posts that cost more that what user is pledging).
def fetch_relevant_posts(page_url, artist)
  posts_data = fanbox(page_url)
  sleep(0.2)
  posts = posts_data.map { |dict| Post.from(dict) }
  posts.select { |post| post.fee_required.positive? && post.fee_required <= artist.fee }
end

# Download a post to a file
def download_post(post, artist)
  post_info = fetch_post_info(post, artist)

  files = post_info.files + post_info.images
  files.each do |file_spec|
    directory = File.dirname(file_spec.filename)
    FileUtils.mkdir_p(directory)
    fanbox(file_spec.url, download: file_spec.filename)
  end

  true
end

def fetch_post_info(post, artist)
  post_info_data = fanbox("/post.info?postId=#{post.id}")
  PostInfo.from(post_info_data, artist)
end

data = fanbox('/plan.listSupporting')
supporting = data.map { |dict| Artist.from(dict) }
total_fee = supporting.reduce(0) { |acc, artist| acc + artist.fee }

puts("Supporting #{supporting.size} artist(s)")
puts("Total fee: #{total_fee} JPY")
puts(SEPARATOR)

supporting.each do |artist|
  if artist.skip?
    puts("Skipping #{artist.name} as requested.")
  else
    fetch_artist_posts(artist)
    sleep(0.2)
  end
  puts(SEPARATOR)
end
