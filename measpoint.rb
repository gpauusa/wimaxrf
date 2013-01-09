
class MeasurementPoint
  attr_reader :key, :value, :type, :description, :code

  def initialize( key, code, type = nil, description = nil )
    @key = key
    @code = code
    @type = type
    @description = description
  end 
  
  def measure
    @value = code.call
  end

  def to_xml
    return"<"+@key+">"+@value+"</"+@key+">\n"
  end

  def to_s
    return @description+": "+@value+"\n"
  end

end