#!/usr/bin/env ruby

START_TIME = Process.clock_gettime(Process::CLOCK_MONOTONIC)

def time_offset_ms
	((Process.clock_gettime(Process::CLOCK_MONOTONIC) - START_TIME) * 1000).round
end

class ResourcePool
	def initialize(size = 1)
		@size = size
		@mutex = Mutex.new
		@condition = ConditionVariable.new
	end
	
	def acquire
		@mutex.synchronize do
			if @size == 0
				timeout = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.1
				
				begin
					remaining = timeout - Process.clock_gettime(Process::CLOCK_MONOTONIC)
					
					if remaining <= 0
						return false
					end
					
					@condition.wait(@mutex, remaining)
				end while @size == 0
			end
			
			@size -= 1
			return true
		end
	end
	
	def release
		@mutex.synchronize do
			@size += 1
			@condition.signal
		end
	end
end

class Worker
	def initialize(name, pool)
		@name = name
		@pool = pool
		@thread = Thread.new { run }
	end
	
	def run
		$stderr.puts "T+#{time_offset_ms} #{@name}: Started"
		
		100.times do |i|
			$stderr.puts "T+#{time_offset_ms} #{@name}: (A) Acquire..."
			if @pool.acquire
				$stderr.puts "T+#{time_offset_ms} #{@name}: (A) Acquired!"
				sleep(0.001)
				$stderr.puts "T+#{time_offset_ms} #{@name}: (A) Release..."
				@pool.release
			else
				$stderr.puts "T+#{time_offset_ms} #{@name}: Timed out!"
			end
			
			$stderr.puts "T+#{time_offset_ms} #{@name}: (B) Acquire..."
			if @pool.acquire
				$stderr.puts "T+#{time_offset_ms} #{@name}: (B) Acquired!"
				sleep(0.001)
				$stderr.puts "T+#{time_offset_ms} #{@name}: (B) Release..."
				@pool.release
			else
				$stderr.puts "T+#{time_offset_ms} #{@name}: Timed out!"
			end
			
			$stderr.puts "T+#{time_offset_ms} #{@name}: (C) Work..."
			sleep(0.01)
		end
	end
	
	def join
		if @thread
			@thread.join
			@thread = nil
		end
	end
end

pool = ResourcePool.new(1)
workers = []

3.times do |i|
	workers << Worker.new("worker-#{i}", pool)
end

workers.each(&:join)
