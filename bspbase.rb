class BSPBase
  @name = nil #name of service
  @info = nil
  @categoryName = nil #name of parameter to retrieve
  @params = {}

  def self.each(&block)
    @params.each &block
  end

  def self.name(n)
    @name = n
  end

  def self.getName
    @name
  end

  def self.info(i)
    @info = i
  end

  def self.getInfo
    @info
  end

  def self.categoryName(n)
    @categoryName = n
  end

  def self.getCategoryName
    @categoryName
  end

  def self.param(pname, opts = {} )
      p = @params ||= {}
      p[pname] = opts.dup
  end

end
