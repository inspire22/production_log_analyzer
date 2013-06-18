module ActionGrep; end

class << ActionGrep

  def grep(action_name, file_name)
    
    # put urls into action paths.  /messages/just_now -> MessagesController#just_now
    if action_name =~ %r#^\/?([^/]+)/(.*)#
      base = $1
      action = $2
      base.sub(/poems|stories/,'Items').sub(/poem|story/,'Item')
      action_name = "#{base[0].upcase}#{base[1..99]}Controller##{action}"
      puts "converted url action_name to #{action_name}"
    end

    unless action_name == 'all' or action_name =~ /\A([A-Z][A-Za-z\d]*)(?:#([A-Za-z]\w*))?\Z/ then
      raise ArgumentError, "Invalid action name #{action_name} expected something like SomeController#action"
    end

    unless File.file? file_name and File.readable? file_name then
      raise ArgumentError, "Unable to read #{file_name}"
    end

    puts "Grepping for #{action_name}\n" + '-'*80+"\n\n"
    
    buckets = Hash.new { |h,k| h[k] = [] }
    comp_count = Hash.new 0

    File.open file_name do |fp|
      fp.each_line do |line|
        #Apr 17 19:50:11 rose rails[14401]: blahblah
        # line =~ / ([^ ]+) ([^ ]+)\[(\d+)\]: (.*)/
        line =~ /^.{15} ([^ ]+) ([^ ]+)\[(\d+)\]: (.*)/        
        # puts "line: #{line}", $1
        next if $2.nil? or $2 == 'newsyslog'
        bucket = [$1, $2, $3].join '-'
        data = $4

        buckets[bucket] << line

        case data
        when /^Start rendering component / then
          comp_count[bucket] += 1
        when /^End of component rendering$/ then
          comp_count[bucket] -= 1
        when /^Completed/ then
          next unless comp_count[bucket] == 0
          action = buckets.delete bucket
          
          if action_name != 'all'
            # next unless action.any? { |l| l =~ /: Processing by #{action_name}/ } 
            next unless action[1] =~ /: Processing by #{action_name}/
          end
          puts "\n"+"-"*80+"\n\n"
          puts action.join
        end
      end
    end
  end

end

