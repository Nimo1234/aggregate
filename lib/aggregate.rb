# Implements aggregate statistics and maintains
# configurable histogram for a set of given samples. Convenient for tracking
# high throughput data.
class Aggregate
  #The current average of all samples
  attr_reader :mean

  #The current number of samples 
  attr_reader :count
  
  #The maximum sample value
  attr_reader :max
  
  #The minimum samples value
  attr_reader :min
  
  #The sum of all samples
  attr_reader :sum

  #The number of samples falling below the lowest valued histogram bucket
  attr_reader :outliers_low

  #The number of samples falling above the highest valued histogram bucket
  attr_reader :outliers_high
 
  # The number of buckets in the binary logarithmic histogram (low => 2**0, high => 2**@@LOG_BUCKETS)
  @@LOG_BUCKETS = 128

  # Create a new Aggregate that maintains a binary logarithmic histogram
  # by default. Specifying values for low, high, and width configures
  # the aggregate to maintain a linear histogram with (high - low)/width buckets
  def initialize (low=nil, high=nil, width=nil)
    @count = 0
    @sum = 0.0
    @sum2 = 0.0
    @outliers_low = 0
    @outliers_high = 0

    # If the user asks we maintain a linear histogram
    if (nil != low && nil != high && nil != width)

      #Validate linear specification
      if high <= low
	raise ArgumentError, "High bucket must be > Low bucket"
      end

      if high - low < width
        raise ArgumentError, "Histogram width must be <= histogram range"
      end

      @low = low
      @high = high
      @width = width
    else
      @low = 1
      @high = to_bucket(@@LOG_BUCKETS - 1)
    end

    #Initialize all buckets to 0
    @buckets = Array.new(bucket_count, 0)
  end

  # Include a sample in the aggregate
  def << data

    # Update min/max
    if 0 == @count
      @min = data
      @max = data
    else
      @max = [data, @max].max
      @min = [data, @min].min
    end

    # Update the running info
    @count += 1 
    @sum += data
    @sum2 += (data * data)

    # Update the bucket
    @buckets[to_index(data)] += 1 unless outlier?(data)
  end

  def mean
    @sum / self.count
  end

  def std_dev
  end

  # Combine two aggregates
  #def +(b)
  #  a = self
  #  c = Aggregate.new

  #  c.count = a.count + b.count
  #end

  #Generate a pretty-printed ASCII representation of the histogram
  def to_s
    #Find the largest bucket and create an array of the rows we intend to print
    max_count = 0
    disp_buckets = Array.new
    @buckets.each_with_index do |count, idx|
      next if 0 == count
      max_count = count if max_count < count
      disp_buckets << [idx, to_bucket(idx), count]
    end

    #Figure out how wide the value and count columns need to be based on their
    #largest respective numbers
    value_width = [disp_buckets.last[1].to_s.length, "value".length].max
    count_width = [max_count.to_s.length, "count".length].max
    max_bar_width  = 80 - (value_width + " |".length + " ".length + count_width)

    #print the header
    header = sprintf("%#{value_width}s", "value")
    header += " |"
    max_bar_width.times { header += "-"}
    header += " count"

    #Determine the value of a '@'
    weight = [max_count.to_f/max_bar_width.to_f, 1.0].max

    #Loop through each bucket to be displayed and output the correct number
    histogram = ""
    prev_index = disp_buckets[0][0] - 1
    disp_buckets.each do |x|

      #Denote skipped empty buckets with a ~
      histogram += "      ~\n" unless prev_index == x[0] - 1
      prev_index = x[0]

      #Add the value
      row = sprintf("%#{value_width}d |", x[1])

      #Add the bar
      bar_size = (x[2]/weight).to_i
      bar_size.times { row += "@"}
      (max_bar_width - bar_size).times { row += " " }

      #Add the count
      row += sprintf(" %#{count_width}d\n", x[2])

      #Append the finished row onto the histogram
      histogram += row
    end

    #Put the pieces together
    "\n" + header + "\n" + histogram 
  end
 
  #Iterate through each bucket in the histogram regardless of 
  #its contents 
  def each
    @buckets.each_with_index do |count, index|
      yield(to_bucket(index), count)
    end
  end

  #Iterate through only the buckets in the histogram that contain
  #samples
  def each_nonzero
    @buckets.each_with_index do |count, index|
      yield(to_bucket(index), count) if count != 0
    end
  end

  private

  def linear?
    nil != @width
  end

  def outlier? (data)

    if data < @low
      @outliers_low += 1
    elsif data > @high
      @outliers_high += 1
    else
      return false
    end
  end

  def bucket_count
    if linear?
      return (@high-@low)/@width
    else
      return @@LOG_BUCKETS
    end
  end

  def to_bucket(index)
    if linear?
      return @low + (index * @width)
    else
      return 2**(index)
    end
  end
    
  def right_bucket? index, data

    # check invariant
    raise unless linear?

    bucket = to_bucket(index)

    #It's the right bucket if data falls between bucket and next bucket
    bucket <= data && data < bucket + @width
  end

=begin
  def find_bucket(lower, upper, target)
    #Classic binary search
    return upper if right_bucket?(upper, target)

    # Cut the search range in half
    middle = (upper/2).to_i

    # Determine which half contains our value and recurse
    if (to_bucket(middle) >= target)
      return find_bucket(lower, middle, target)
    else
      return find_bucket(middle, upper, target)
    end
  end
=end

  # A data point is added to the bucket[n] where the data point
  # is less than the value represented by bucket[n], but greater
  # than the value represented by bucket[n+1]
  def to_index (data)

    # basic case is simple
    return log2(data).to_i if !linear?

    # Search for the right bucket in the linear case
    @buckets.each_with_index do |count, idx|
      return idx if right_bucket?(idx, data)
    end
    #find_bucket(0, bucket_count-1, data)

    #Should not get here
    raise "#{data}"
  end

  # log2(x) returns j, | i = j-1 and 2**i <= data < 2**j
  def log2( x )
   Math.log(x) / Math.log(2)
  end
 
end