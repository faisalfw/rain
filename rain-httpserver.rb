
# Bismillahirrohmanirrohim

# rain-httpserver.rb
# created by faisal w, at 2020 october
# 
# simple web server, beginner,
# static web server, cara kerjanya adalah: 
# ada direktori "root-public-document", didalamnya terdapat se
# mua resource yang mungkin klien me request nya, jika yang di
# request client adalah file other than .html extension file,
# maka file nya diberikan tanpa ada modifikasi, bila yang dimi
# nta adalah file berekstensikan .html, maka ada prosedur tamb
# ahan, yaitu ada modifikasi, seperti isinya di read dan di ma
# sukkan ke skeleton/template.
#
# cara menjalankanya adalah:
#   Rain::HTTPServer.run()
#    # done!
#
# server ini punya banyak drawback, seperti:
# > keamanan yang parah
# > pengecekan user input, yaitu di HTTP requestnya
# > fitur yang sedikit di implementasi HTTP nya
# > dan lain lain
# > itu karena aku muales.
# 
# Woow, isnt that awesome!


require "colorize"
require "pp"
require "socket"
require "pstatus"
require "time.rb"
require "mini_mime"
require "thread"
require "digest"

Thread.abort_on_exception = true

module Rain
  NAME = "Rain/1.0"
  RV = false # rain verbose
  DEVELOPMENT = false

  module Constant
    HTTP_VERSION = "HTTP/1.1"
    CRLF  = "\r\n"
    CR    = "\r"
    LF    = "\n"
  end

  class HTTPServer
    READ_BUFFER    = 4096 * 5
    HOST          = "127.0.0.1"
    PORT          = 4453

    CONNECTION_TIMEOUT  = 40

    def self.run
      @@server_socket = TCPServer.new(HOST, PORT)
      puts "#{Time.now} - Rain server is listening on #{HOST.bold}:#{PORT.to_s.green.bold} ..."
      loop {
        client_socket = @@server_socket.accept
        puts ">> New client socket :" if RV
        print_status(client_socket, nil, nil) if RV
        passing_LOGIC_OPERATION(client_socket)
      }
    end

    def self.passing_LOGIC_OPERATION(client_socket)
      Thread.new(client_socket) {
        begin
          Thread.current["callback"] = proc { |thread|
            if thread["exit_status"] != 0
              puts ">> Timeout reached for :" if RV
              print_status(client_socket, nil, nil) if RV
            end
            client_socket.close
          }
          Thread.current["timeout"] = CONNECTION_TIMEOUT
          ThreadObserver.add Thread.current

          request_obj    = read_and_parse_request(client_socket)
          response_obj  = Response.new(request_obj)

          unless ['HTTP/1.0', 'HTTP/1.1'].include?(request_obj.http_version)
            # 505 HTTP Version Not Supported
            send_response(client_socket, http_response_for_error(505, request_obj))
            Thread.current.terminate
          end

          unless ['GET', 'HEAD'].include?(request_obj.http_method)
            # 501 Not Implemented
            send_response(client_socket, http_response_for_error(501, request_obj))
            Thread.current.terminate
          end

          if request_obj.http_version == 'HTTP/1.0'
            response_obj.response_header["host"] = nil
            send_response(client_socket, response_obj.to_s)
            print_status(client_socket, request_obj, response_obj, verbose = false)
          elsif request_obj.http_version == 'HTTP/1.1'
            if request_obj.connection == 'close'
              send_response(client_socket, response_obj.to_s)
              print_status(client_socket, request_obj, response_obj, verbose = false)
            elsif request_obj.connection == 'keep-alive'

              timeout = 10
              max_requests = 25
              closing_approach = false
              
              max_requests.downto(0) {|n|
                response_obj = Response.new(request_obj)
                if n == 0 or closing_approach
                  response_obj.response_header["connection"] = "close"
                else
                  response_obj.response_header["connection"] = "keep-alive"
                  response_obj.response_header["keep-alive"] = "timeout=#{timeout}, max=#{n}"
                end
                send_response(client_socket, response_obj.to_s)
                print_status(client_socket, request_obj, response_obj, verbose = false)
                if response_obj.response_header["connection"] == "close"
                  break
                end
                Thread.current["timeout"] = timeout
                request_obj = read_and_parse_request(client_socket)
                closing_approach = true if request_obj.connection == "close"
              }
            end
          end

          Thread.current["exit_status"] = 0

        rescue ThreadObserver::RainTimeout
          # code in this RainTimeout rescue wont run if the thread
          # exit before timeout reached, that's why i put the code 
          # that should be here, inside callback.
        rescue Exception
          if DEVELOPMENT
            puts "------------------------------------------------"
            puts "#{$!.class}: #{$!}"
            $!.backtrace.each do |trace|
              puts "  => #{trace}"
            end
            puts
          end
        end
      }
    end

    def self.read_and_parse_request(client_socket)
      http_request = String.new
      loop {
        r = client_socket.readpartial(READ_BUFFER)
        http_request << r
        break if http_request.include?(Constant::CRLF*2)
      }
      return Request.new(http_request)
    end

    def self.send_response(client_socket, str)
      client_socket.write(str)
      sleep(1)
    end

    def self.http_response_for_error(response_code, request_obj)
      http_version = (response_code == 505) ? Constant::HTTP_VERSION : request_obj.http_version
      document = ResponseCode.create_document(response_code, request_obj)
      response_line = "#{http_version} #{response_code} " +
        Pstatus::MESSAGE[response_code]
      headers = ""
      {
        "content-type"      => "text/html",
        "content-length"    => document.bytesize,
        "server"            => Rain::NAME,
        "connection"        => "close",
        "date"              => Time.now.httpdate.to_s
      }.each do |k,v|
        headers << "#{k}: #{v}#{Constant::CRLF}"
      end
      return response_line + Constant::CRLF +
        headers + Constant::CRLF +
        document
    end

    def self.print_status(client_socket, request_obj, response_obj, verbose=true)
      if verbose
        if client_socket
          puts "Client Name:"
          client_address_s = 
            "#{client_socket.peeraddr[3].bold}:#{client_socket.peeraddr[1].to_s.green.bold}"
          puts client_address_s
          puts
        end

        if request_obj
          puts "Request:"
          pp request_obj
          puts
        end

        if response_obj
          puts "Response:"
          puts "response code: #{response_obj.response_code}"
          response_obj.response_header.each {|k,v|
            puts "#{k}: #{v}#{v.nil? ? "nil" : ""}"
          }
          puts
        end
      else

        # TIME - CLIENT-NAME : HTTP-METHOD /PATH [RESPONSE CODE] CONTENT-LENGTH

        log = String.new
        log << Time.now.to_s << " - "

        if client_socket
          log << "#{client_socket.peeraddr[3]}:#{client_socket.peeraddr[1]} : "
        end

        if request_obj
          log << "#{request_obj.http_method} #{request_obj.path} "
        end

        if response_obj
          log << 
            "[#{response_obj.response_code}] #{
            response_obj.response_header["content-length"]}"
        end

        puts log
      end
    end
  end # end of HTTPServer class definition  

  class Request
    attr_reader :http_method, :request_uri, :http_version, :path

    def initialize(request_header)
      @request_header = "".replace(request_header)

      request_line = request_header.split(Constant::CRLF)[0].strip
      if request_line =~ /^([a-z]+)\s*(\S+)\s*(\S+)/i
        @http_method, @request_uri, @http_version = $1, $2, $3
        @path = URI.decode(URI(@request_uri).path)
        @path = (@path == '/') ? '/index.html' : @path

        @http_method.upcase!
        @http_version.upcase!
      end
    end

    def method_missing(name, *args)
      name = name.to_s
      name.gsub!("_", "-")
      regex_field_s_value = /^\s*#{name}\s*:(.*)/i
      @request_header.split(Constant::CRLF)[1..-1].each do |line|
        if m = line.match(regex_field_s_value)
          return m[1].strip
        end
      end
      return nil
    end
  end

  class Response
    attr_accessor :response_code, :response_header
    def initialize(request_obj)
      @request_obj = request_obj
      @response_header = {
        "host"            => "#{Rain::HTTPServer::HOST}:#{Rain::HTTPServer::PORT}",
        "server"          => Rain::NAME,
        "content-type"    => nil, #
        "content-length"  => nil, #
        "connection"      => "close",
        "last-modified"    => nil, #
        "etag"            => nil, #
        "date"            => Time.now.httpdate.to_s,
      }
      @response_code  = nil
      @document        = nil
      prepare_response()

      # just to make my code simpler
      if [400, 404, 410].include?(@response_code)
        @document        = ResponseCode.create_document(@response_code, @request_obj)
        @response_header["content-type"]    = "text/html"
        @response_header["content-length"]  = @document.bytesize
      end

      @document = "" if @request_obj.http_method == 'HEAD'
        # koyoe content-length perlu tak edit sisan?
        # ternyata ra perlu, atas dasar? apache web server
    end

    def prepare_response()
      # sequences is now correct

      if @request_obj.http_version == 'HTTP/1.1' and @request_obj.host == nil
        @response_code  = 400 # Bad Request
        return
      end

      if Filesystem::GONE.include?(@request_obj.path)
        @response_code  = 410 # Gone
        return
      end

      io = Filesystem.fetch(@request_obj.path)

      if io
        last_modified = io.mtime.httpdate.to_s
        if @request_obj.if_modified_since == last_modified
          @response_code  = 304 # Not Modified
          return
        end

        etag = Filesystem.fetch_etag(@request_obj.path)
        if @request_obj.if_none_match == etag
          @response_code  = 304
          @response_header["etag"]  = etag
          return
        end

        @response_code  = 200
        @document        = io.read
        @response_header["content-type"]    = MimeType.fetch(@request_obj.path)
        @response_header["content-length"]  = @document.bytesize
        @response_header["last-modified"]    = last_modified
        @response_header["etag"]            = etag

        if File.extname(@request_obj.path) == '.html'
          @document = HTML_document_procedure(@request_obj.path, @document)
          @response_header["content-length"] = @document.bytesize
        end
        return
      end

      if io.nil?
        @response_code  = 404 # Not Found
        return
      end

    end # end of prepare_response()

    def HTML_document_procedure(path, only_CONTENT)
      complete_HTML_and_CSS_skeleton = Filesystem.fetch(
        Filesystem::Bookmark::COMPLETE_SKELETON
      ).read
      title_regexp    = /\(RainTitleSign12345\)/
      article_regexp  = /\(RainArticleSign12345\)/

      only_CONTENT = Plugin.only_CONTENT_filtering(only_CONTENT)

      title = File.basename(path, File.extname(path)).capitalize
      complete_HTML_and_CSS_skeleton.sub!(title_regexp, title)
      complete_HTML_and_CSS_skeleton.sub!(article_regexp, 
        "<h1>#{title}</h1>" + only_CONTENT)
      return complete_HTML_and_CSS_skeleton
    end    

    def to_s
      response_line = "#{@request_obj.http_version} #{@response_code} " +
        Pstatus::MESSAGE[@response_code]
      headers = ""
      @response_header.each {|k,v| headers << "#{k}: #{v}#{Constant::CRLF}" if v != nil }
      return response_line + Constant::CRLF +
        headers + Constant::CRLF +
        ( @document != nil ? @document : "" )
    end

  end # end of Response class definition  

  # This class acts just like `Kenbunshoku no Haki'
  class ThreadObserver
    class RainTimeout < Exception
    end

    @@array = []

    def self.add thread
      @@array << thread
    end

    def self.observe
      Thread.new {  
        loop {
          sleep(1)
          @@array.delete_if do |thread|
            begin
              thread["timeout"] -= 1
              if thread["timeout"] == 0
                thread.raise RainTimeout
                thread["callback"].call(thread) if thread["callback"]
                  # callback should not use much of time even half second!
                true
              else
                false
              end
            rescue Exception
              # an ignorance
            end
          end
        }
      }
    end
  end  

  class ResponseCode
    def self.create_document(status_code, request_obj)
      return <<-DELIMITER
        <h1>#{status_code}: #{Pstatus::MESSAGE[status_code]}</h1>
        <h2>Client Debug: <br />
          Method: #{request_obj.http_method} <br />
          Request URI: #{request_obj.request_uri} <br />
          HTTP Version: #{request_obj.http_version}
        </h2>
      DELIMITER
    end
  end

  class MimeType
    def self.fetch(filename)
      if c = MiniMime.lookup_by_filename(filename)
        return c.content_type
      else
        return "application/octet-stream"
      end
    end
  end  

  # Read only filesystem
  class Filesystem
    ROOT_PUBLIC_DOCUMENT = "./root-public-document/"

    module Bookmark
      COMPLETE_SKELETON = 'complete_HTML_and_CSS_skeleton.html'
    end

    GONE = [
      # file file yang 'gone'
    ]

    def self.scan_dir(directory)
      dir = Dir.new(directory)
      dir.each do |file|
        next if file == '.' or file == '..'
        full_file = File.join(directory, file)
        if File.directory?(full_file)
          scan_dir(full_file)
        elsif File.file?(full_file)
          @@all_files << full_file
          fhandle = File.open(full_file)
          @@etags[full_file] = Digest::SHA256.base64digest(
            "#{fhandle.read} #{fhandle.mtime.to_f}"
          )
        end
      end
    end

    def self.prepare
      @@all_files = []
      @@etags      = {}
      scan_dir(ROOT_PUBLIC_DOCUMENT)
    end

    def self.fetch(doc_path)
      # doc_path = "/index.html" if doc_path == "/"
      doc_path = File.join(ROOT_PUBLIC_DOCUMENT, doc_path)
      return File.open(doc_path) if @@all_files.include?(doc_path)
      return nil
    end

    def self.fetch_etag(doc_path)
      return @@etags[File.join(ROOT_PUBLIC_DOCUMENT, doc_path)]
    end

    ####

    def self.all_files
      return @@all_files
    end

    def self.etags
      return @@etags
    end
  end  

  module Plugin
    # -----------kode plugin--------------------

    class TraverseServer
      def self.call(match)
        ret = "<p>"
        Filesystem.all_files.grep(/#{match}/i).each do |m|
          ret << "#{m}<br />"
        end
        return ret + "</p>"
      end
    end

    # ------------caller-------------------

    def self.TraverseServer(arg)
      return TraverseServer.call(arg)
    end

    # -------------------------------

    def self.only_CONTENT_filtering(only_CONTENT)
      only_CONTENT = "".replace(only_CONTENT)
      plugin_regexp = /(\(%plugin (.*) plugin-end%\))/i
      m = only_CONTENT.scan(plugin_regexp)
      return only_CONTENT if m.size.zero?
      m.each do |m|
        only_CONTENT.sub!(m[0], eval(m[1]))
      end
      return only_CONTENT
    end

  end

  ###################################################################

  Filesystem.prepare
  ThreadObserver.observe
end

########## Main ##########

puts
Rain::HTTPServer.run
