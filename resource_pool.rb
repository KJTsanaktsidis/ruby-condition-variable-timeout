# Uses the same acquire/release flow as Sequel::ThreadedConnectionPool
class ResourcePool
	class TimeoutError < StandardError; end

	def initialize(pool_size:, timeout:)
		@available_resources = pool_size.times.map { |n| "resource-#{n}" }
		@timeout = timeout
		@mutex = Thread::Mutex.new
		@waiter = Thread::ConditionVariable.new
	end

	def with_resource
		resource = acquire
		yield resource
	ensure
		if resource
			release(resource)
		end
	end

	private

	def acquire
		@mutex.synchronize do
			if resource = next_available
				Logger.debug('Pool: Acquired resource without waiting')
				return resource
			end
			
			timeout = @timeout
			start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
			
			Logger.debug('Pool: Waiting')
			@waiter.wait(@mutex, timeout)
			
			if resource = next_available
				Logger.debug('Pool: Acquired resource after waiting')
				return resource
			end

			loop do
				elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

				if elapsed > timeout
					raise TimeoutError, "Unable to acquire resource after #{elapsed} seconds"
				end

				Logger.debug('Pool: Woken by signal but resource unavailable. Waiting again.')
				@waiter.wait(@mutex, timeout - elapsed)
				if resource = next_available
					Logger.debug('Pool: Acquired resource after multiple waits')
					return resource
				end
			end
		end
	end

	def release(resource)
		@mutex.synchronize do
			@available_resources << resource
			Logger.debug('Pool: Released resource. Signaling.')
			@waiter.signal
		end
		
		# Introducing this allows the signalled thread to pick up the resource:
		# Thread.pass
	end

	def sync_next_available
		@mutex.synchronize do
			next_available
		end
	end

	def next_available
		@available_resources.pop
	end
end
