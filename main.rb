#!/usr/bin/env ruby

require 'colorize'
require 'fiber/annotation'

require_relative 'resource_pool'

POOL = ResourcePool.new(pool_size: 1, timeout: 0.1)
WORKER_COUNT = 3
MAX_TEST_DURATION = 2.0
LOG_COLORS = [:light_blue, :light_magenta, :light_green, :light_red, :light_cyan, :light_yellow, :blue, :magenta, :green, :red, :cyan, :yellow]

class Logger
	def self.debug(message)
		fiber = Fiber.current
		color = Thread.current[:log_color]
		puts "[#{Time.now}] #{Fiber.current.annotation}: #{message}".colorize(color)
	end
end

workers = []

class Clock
	def initialize
		@start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
	end
	
	def total
		Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start
	end
end

clock = Clock.new

WORKER_COUNT.times do |n|
	workers << Thread.new do
		Fiber.annotate("worker-#{n}")
		
		Thread.current[:log_color] = LOG_COLORS[n]

		begin
			while clock.total < MAX_TEST_DURATION do
				# (2) (worker-1) is woken up
				POOL.with_resource do # (3) Try to lock but can't.
					Logger.debug('Sleep with resource #1')
					sleep(0.001) # simulates a DB call
				end # (0) ConditionVariable#signal (worker-0)
				
				POOL.with_resource do # (1) Immediately re-acquire the mutex here.
					Logger.debug('Sleep with resource #2')
					sleep(0.001) # simulates a DB call
				end
				
				Logger.debug('Sleep without resource')
				sleep(0.001) # simulates some other IO
			end
		rescue ResourcePool::TimeoutError => e
			Logger.debug("Timed out. Aborting test after #{clock.total} seconds")
			puts "#{e.class} #{e.message}"
			puts e.backtrace
			STDOUT.flush
			Kernel.exit!
		end
	end
end

workers.each(&:join)
