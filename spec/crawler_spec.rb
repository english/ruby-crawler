# frozen_string_literal: true

# @!domain RSpec::Matchers

require 'webrick'
require 'uri'
require 'rspec'
require 'crawler'

describe Crawler do
  def with_fixture_server
    server = WEBrick::HTTPServer.new(
      BindAddress: '0.0.0.0',
      Port: 8000,
      DocumentRoot: File.expand_path('fixtures', __dir__),
      Logger: WEBrick::Log.new('/dev/null')
    )
    server_thread = Thread.new { server.start }
    server_thread.abort_on_exception = true
    yield(server_thread)
  rescue => e
    puts "error #{e}"
  ensure
    server&.shutdown
    server_thread&.join
  end

  it 'crawls a simple site' do
    executor = Concurrent::ImmediateExecutor.new
    results = []

    with_fixture_server do
      f = described_class.crawl(URI('http://localhost:8000/'), executor) do |result|
        results << result
      end
      f.value
    end

    expect(results).to contain_exactly(
      a_hash_including(
        uri: 'http://localhost:8000/',
        assets: []
      ),
      a_hash_including(
        uri: 'http://localhost:8000/a.html',
        assets: a_collection_containing_exactly(
          URI('http://localhost:8000/a.js'),
          URI('http://localhost:8000/a.css')
        )
      ),
      a_hash_including(
        uri: 'http://localhost:8000/b.html',
        assets: a_collection_containing_exactly(
          URI('http://localhost:8000/b.js'),
          URI('http://localhost:8000/b.css')
        )
      ),
      a_hash_including(
        uri: 'http://localhost:8000/c.html',
        assets: a_collection_containing_exactly(
          URI('http://localhost:8000/c.js'),
          URI('http://localhost:8000/c.css')
        )
      )
    )
  end
end
