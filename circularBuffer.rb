

class CircularBuffer

  def initialize(length)
    @buf = Array.new(length)
    @length = length
    @size = 0
    @next = 0
  end

  def push(item)
    @buf[@next] = item
    @next += 1
    @next = 0 if (@next >= @length) 
    @size += 1 if (@size < @length) 
#    puts @buf.inspect
  end

  def to_a
    if (@size < @length)
      a = @buf.slice(0, @size)
    else 
      puts "next: #@next size: #@size"
      a = @buf.slice(@next, @size)
      if (@next > 0)
        a.concat(@buf.slice(0, @next))
      end
    end
    a
  end
end

if $0 == __FILE__
  puts "HI"

  b = CircularBuffer.new(3)
  (1..10).each do |i| 
    b.push i 
    puts "to_a #{b.to_a().inspect}"
  end
end

    