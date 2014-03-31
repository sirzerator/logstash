require "test_utils"
require "logstash/filters/multiline"

describe LogStash::Filters::Multiline do

  extend LogStash::RSpec

  describe "simple multiline" do
    config <<-CONFIG
    filter {
      multiline {
        pattern => "^\\s"
        what => previous
      }
    }
    CONFIG

    sample [ "hello world", "   second line", "another first line", "not linked to previous" ] do
      insist { subject.length } == 2
      insist { subject[0]["message"] } == "hello world\n   second line"
      insist { subject[0]["tags"] }.include?("multiline")
      insist { subject[1]["message"] } == "another first line"
      reject { subject[1] }.include?("tags")
    end
  end

  describe "multiline with add_tag" do
    config <<-CONFIG
    filter {
      multiline {
        pattern => "^\\s"
        what => previous
        add_tag => [ "test" ]
      }
    }
    CONFIG

    sample [ "hello world", "   second line", "another first line", "not linked to previous" ] do
      insist { subject.length } == 2
      insist { subject[0]["message"] } == "hello world\n   second line"
      insist { subject[0]["tags"] }.include?("test")
      insist { subject[1]["message"] } == "another first line"
      reject { subject[1] }.include?("tags")
    end
  end

  describe "multiline with add_field" do
    config <<-CONFIG
    filter {
      multiline {
        pattern => "^\\s"
        what => previous
        add_field => [ "test", "value" ]
      }
    }
    CONFIG

    sample [ "hello world", "   second line", "another first line", "not linked to previous" ] do
      insist { subject.length } == 2
      insist { subject[0]["message"] } == "hello world\n   second line"
      insist { subject[0] }.include?("test")
      insist { subject[0]["test"] } == "value"
      insist { subject[1]["message"] } == "another first line"
      reject { subject[1] }.include?("test")
    end
  end

  describe "multiline using grok patterns" do
    config <<-CONFIG
    filter {
      multiline {
        pattern => "^%{NUMBER} %{TIME}"
        negate => true
        what => previous
      }
    }
    CONFIG

    sample [ "120913 12:04:33 first line", "second line", "third line", "120913 12:05:25 another event", "120913 12:05:25 yet another event" ] do
      insist { subject.length } == 2
      insist { subject[0]["message"] } ==  "120913 12:04:33 first line\nsecond line\nthird line"
      insist { subject[1]["message"] } ==  "120913 12:05:25 another event"
    end
  end

  describe "multiline using named grok patterns" do
    config <<-CONFIG
    filter {
      multiline {
        pattern => "^%{NUMBER:first} %{TIME:second}"
        negate => true
        what => previous
      }
    }
    CONFIG

    sample [ "120913 12:04:33 first line", "second line", "third line", "120913 12:05:25 another event", "120913 12:05:25 yet another event" ] do
      insist { subject.length } == 2
      insist { subject[0]["message"] } ==  "120913 12:04:33 first line\nsecond line\nthird line"
      insist { subject[0] }.include?("first")
      insist { subject[0]["first"] } == "120913"
      insist { subject[0] }.include?("second")
      insist { subject[0]["second"] } == "12:04:33"
      insist { subject[1]["message"] } ==  "120913 12:05:25 another event"
    end
  end

  describe "multiline safety among multiple concurrent streams" do
    config <<-CONFIG
      filter {
        multiline {
          pattern => "^\\s"
          what => previous
        }
      }
    CONFIG

    multiline_event = [
      "hello world",
    ]

    count = 20
    stream_count = 2
    id = 0
    eventstream = count.times.collect do |i|
      stream = "stream#{i % stream_count}"
      (
        [ "hello world #{stream}" ] \
        + rand(5).times.collect { |n| id += 1; "   extra line #{n} in #{stream} event #{id}" }
      ) .collect do |line|
        LogStash::Event.new("message" => line,
                            "host" => stream, "type" => stream,
                            "event" => i)
      end
    end

    alllines = eventstream.flatten

    # Take whole events and mix them with other events (maintain order)
    # This simulates a mixing of multiple streams being received
    # and processed. It requires that the multiline filter correctly partition
    # by stream_identity
    concurrent_stream = eventstream.flatten.count.times.collect do
      index = rand(eventstream.count)
      event = eventstream[index].shift
      eventstream.delete_at(index) if eventstream[index].empty?
      event
    end

    sample concurrent_stream do
      insist { subject.count } == count
      subject.each_with_index do |event, i|
        #puts "#{i}/#{event["event"]}: #{event.to_json}"
        #insist { event.type } == stream
        #insist { event.source } == stream
        insist { event["message"].split("\n").first } =~ /hello world /
      end
    end
  end

  describe "multiline add/remove tags and fields only when matched" do
    config <<-CONFIG
      filter {
        mutate {
          add_tag => "dummy"
        }
        multiline {
          add_tag => [ "nope" ]
          remove_tag => "dummy"
          add_field => [ "dummy2", "value" ]
          pattern => "an unlikely match"
          what => previous
        }
      }
    CONFIG

    sample [ "120913 12:04:33 first line", "120913 12:04:33 second line", "" ] do
      subject.each do |s|
        insist { s["tags"] }.include?("dummy")
        reject { s["tags"] }.include?("dummy2")
        reject { s }.include?("dummy2")
      end
    end
  end 
end
