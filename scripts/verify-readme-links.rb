#!/usr/bin/env ruby
# frozen_string_literal: true

# Extracts Markdown links [text](url) from README.md and checks HTTP status.
# URLs may contain ')' if escaped in Markdown; this parser handles common cases.
# Usage: ruby scripts/verify-readme-links.rb

require "net/http"
require "uri"
require "openssl"

readme = File.read(File.join(__dir__, "..", "README.md"))
urls = readme.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.map(&:strip).uniq.reject { |u| u.start_with?("#") }

results = { ok: [], redirect: [], soft_fail: [], hard_fail: [] }

urls.each do |raw|
  uri = URI.parse(raw)
  next if uri.scheme.nil? || !%w[http https].include?(uri.scheme)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 20
  http.read_timeout = 20
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER

  path = uri.path
  path = "/" if path.empty?
  path = "#{path}?#{uri.query}" if uri.query

  begin
    res = http.request_head(path)
    code = res.code.to_i
    case code
    when 200..299
      results[:ok] << raw
    when 300..399
      results[:redirect] << "#{raw} -> #{code}"
    when 403
      results[:soft_fail] << "#{raw} (#{code} — often blocks bots; check in browser)"
    when 404, 410
      results[:hard_fail] << "#{raw} (#{code})"
    else
      results[:soft_fail] << "#{raw} (#{code})"
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
    results[:soft_fail] << "#{raw} (timeout: #{e.class})"
  rescue StandardError => e
    results[:hard_fail] << "#{raw} (error: #{e.class}: #{e.message})"
  end
end

puts "Checked #{urls.size} unique http(s) URLs from README.md\n\n"
puts "OK (#{results[:ok].size}):"
results[:ok].sort.each { |u| puts "  #{u}" }
puts "\nRedirects (#{results[:redirect].size}):"
results[:redirect].sort.each { |u| puts "  #{u}" }
puts "\nSoft failures (#{results[:soft_fail].size}):"
results[:soft_fail].sort.each { |u| puts "  #{u}" }
puts "\nHard failures (#{results[:hard_fail].size}):"
results[:hard_fail].sort.each { |u| puts "  #{u}" }

exit(results[:hard_fail].empty? ? 0 : 1)
