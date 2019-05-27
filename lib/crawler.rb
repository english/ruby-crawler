# frozen_string_literal: true

require 'concurrent-ruby'
require 'net/http/persistent'
require 'nokogiri'
require 'uri'
# require 'speculation'

module Crawler
  def self.same_domain?(test_uri, candidate_uri)
    candidate_uri.host.nil? ||
      candidate_uri.relative? ||
      candidate_uri.host == test_uri.host
  end

  def self.page_assets(doc, page_uri)
    doc.
      css('img, script, link[rel=stylesheet]').
      map { |el| el['href'] || el['src'] }.
      reject { |url| url.nil? || url.empty? || url.start_with?('#') }.
      map { |url| normalise_uri(page_uri, URI.parse(url)) }
  end

  def self.normalise_uri(page_uri, uri)
    normalised = page_uri.merge(uri)
    normalised.normalize!
    normalised.fragment = nil
    normalised.query = nil
    normalised
  end

  def self.page_links(doc, page_uri)
    doc.
      css('a').
      map { |anchor| URI.parse(anchor['href']) rescue nil }.
      reject(&:nil?).
      map { |uri| normalise_uri(page_uri, uri) }.
      select { |link_uri| link_uri.host == page_uri.host }
  end

  def self.analyze_page_body(html, page_uri)
    doc = Nokogiri::HTML::Document.parse(html)

    {
      assets: page_assets(doc, page_uri),
      links: page_links(doc, page_uri)
    }
  end

  def self.wait_on_nested_futures(f)
    case f
    when Array
      f.flat_map(&method(:wait_on_nested_futures))
    when Concurrent::Promises::Future
      wait_on_nested_futures(f.value || f.reason)
    else
      f
    end
  end

  def self.just_once(seen, uri)
    return if seen.include?(uri)
    seen << uri
    yield
  end

  def self._crawl(uri, init_uri, executor, seen, http, &block)
    Concurrent::Promises
      .future_on(executor) { just_once(seen, uri) { http.request(uri) } }
      .then_on(executor) { |resp|
        if resp&.code == '200'
          parsed = analyze_page_body(resp.body, uri).merge(uri: uri.to_s)
          block.call(parsed.slice(:uri, :assets))
          unseen_links = parsed[:links] - seen.to_a
          Concurrent::Promises.zip_futures_on(
            executor,
            Concurrent::Promises.fulfilled_future(parsed),
            *unseen_links.map { |l| _crawl(l, init_uri, executor, seen, http, &block) }
          )
        end
      }.rescue { |error| block.call(uri: uri, error: error) }
  end

  def self.crawl(init_uri, executor, &block)
    seen = Concurrent::Set[]

    Concurrent::Promises.future_on(executor) do
      http = Net::HTTP::Persistent.new
      wait_on_nested_futures(_crawl(init_uri, init_uri, executor, seen, http, &block))
    end
  end

  # Speculation.fdef method(:crawl),
  #   args: Speculation.cat(init_uri: URI, executor: Concurrent::AbstractExecutorService),
  #   block: Proc
end
