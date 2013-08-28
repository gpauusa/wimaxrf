#
# Copyright (c) 2006-2009 National ICT Australia (NICTA), Australia
# Copyright (c) 2004-2009 WINLAB, Rutgers University, USA
# Copyright (c) 2012-2013 University of California, Los Angeles, USA
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
#
# Library of client side helpers
#
require 'fcntl'
require 'omf-common/mobject'

#
# Run an application on the client.
#
# Borrows from Open3
#
class ExecApp < MObject

  # Holds the pids for all active apps
  @@apps = {}

  # True if this active app is being killed by a proper
  # call to ExecApp.killAll() or kill()
  # (i.e. when the caller of ExecApp decided to stop the application,
  # as far as we are concerned, this is a 'clean' exit)
  @cleanExit = false

  def self.[](id)
    app = @@apps[id]
    if app.nil?
      error("Unknown application '#{id}/#{id.class}'")
    end
    app
  end

  def self.killAll(signal = 'KILL')
    @@apps.each_value { |app|
      app.kill(signal)
    }
  end

  def kill(signal = 'KILL')
    @cleanExit = true
    debug("Sending #{signal} to application '#{@id}'")
    Process.kill(signal, @pid)
  end

  def stdin(line)
    debug("Writing '#{line}' to app '#{@id}'")
    @stdin.write("#{line}\n")
    @stdin.flush
  end

  #
  # Run an application 'cmd' in a separate thread and monitor
  # its stdout. Also send status reports to the 'observer' by
  # calling its "onAppEvent(eventType, appId, message)"
  #
  # @param id ID of application (used for reporting)
  # @param observer Observer of application's progress
  # @param cmd Command path and args
  # @param mapStderrToStdout If true report stderr as stdout [false]
  #
  def initialize(id, observer, cmd, mapStderrToStdout = false)
    @id = id
    @observer = observer
    @@apps[id] = self

    pw = IO::pipe   # pipe[0] for read, pipe[1] for write
    pr = IO::pipe
    pe = IO::pipe

    info("Starting application '#{id}' - cmd: '#{cmd}'")
    @pid = fork {
      # child will remap pipes to std and exec cmd
      pw[1].close
      STDIN.reopen(pw[0])
      pw[0].close

      pr[0].close
      STDOUT.reopen(pr[1])
      pr[1].close

      pe[0].close
      STDERR.reopen(pe[1])
      pe[1].close

      begin
        exec(cmd)
      rescue => e
        error("exec() failed: #{e.message}\n\t#{e.backtrace.join("\n\t")}")
      end
      # Should never get here
      exit!
    }
    notify('STARTED', @id, @pid)

    pw[0].close
    pr[1].close
    pe[1].close
    monitorAppPipe('stdout', pr[0])
    monitorAppPipe(mapStderrToStdout ? 'stdout' : 'stderr', pe[0])

    # Start a thread that waits for the application to exit
    Thread.new(id, @pid) do |id, pid|
      p, status = Process.waitpid2(pid)
      @@apps.delete(@id)
      if status.success? || @cleanExit
        s = 'OK'
        info("Application '#{id}' finished")
      else
        s = 'ERROR'
        error("Application '#{id}' failed (exitstatus=#{status.exitstatus})")
      end
      notify("DONE.#{s}", @id, status)
    end

    @stdin = pw[1]
  end

  private

  #
  # Create a thread to monitor the process and its output
  # and report that back to the server
  #
  # @parma name Name of app stream to monitor (should be stdout, stderr)
  # @param pipe Pipe to read from
  #
  def monitorAppPipe(name, pipe)
    Thread.new {
      begin
        loop do
          s = pipe.readline.chomp
          notify(name, @id, s)
        end
      rescue EOFError
        # do nothing
      rescue => e
        error("Exception in monitorAppPipe(#{@id}): #{e.message}\n\t#{e.backtrace.join("\n\t")}")
      ensure
        pipe.close
      end
    }
  end

  #
  # Notifies application events to the observer
  #
  def notify(*args)
    if @observer
      begin
        @observer.onAppEvent(*args)
      rescue => e
        error("Exception in onAppEvent(#{args.join(', ')}): #{e.message}\n\t#{e.backtrace.join("\n\t")}")
      end
    end
  end

end


if $0 == __FILE__
  MObject.initLog('test')

  class TestMock
    def onAppEvent (name, id, msg = nil)
      puts "onAppEvent: name => '#{name}' id => '#{id}' msg => '#{msg}'"
    end
  end

#  w = ExecApp.new(:testApp, TestMock.new, "ping -c 3 external1")
  w = ExecApp.new(:commServer, TestMock.new, '../c/commServer/commServer -d 8 -l - --iface eth1')
#  w = ExecApp.new(:testApp, "foo -c")
  gets
  puts "Threads: #{Thread.list.join(', ')}"
end
