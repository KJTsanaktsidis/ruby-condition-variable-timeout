#include <cstdio>
#include <ctime>
#include <iostream>
#include <string>
#include <pthread.h>
#include <unistd.h>

struct timespec g_start_time;

long time_offset_ms() {
	struct timespec now;
	clock_gettime(CLOCK_REALTIME, &now);
	
	long seconds = now.tv_sec - g_start_time.tv_sec;
	long nanoseconds = now.tv_nsec - g_start_time.tv_nsec;
	
	return (seconds * 1000000000 + nanoseconds) / 1000000;
}

class ResourcePool {
	int _size;
	pthread_mutex_t _mutex;
	pthread_cond_t _condition;
	
public:
	ResourcePool(int size = 1) : _size(size) {
		pthread_mutex_init(&_mutex, NULL);
		pthread_cond_init(&_condition, NULL);
	}
	
	~ResourcePool() {
		pthread_mutex_destroy(&_mutex);
		pthread_cond_destroy(&_condition);
	}
	
	bool acquire() {
		pthread_mutex_lock(&_mutex);
		// fprintf(stderr, "T+%ld ResourcePool: Acquire %d...\n", time_offset_ms(), _size);
		
		if (_size == 0) {
			struct timespec timeout;
			clock_gettime(CLOCK_REALTIME, &timeout);
			
			// Add 100ms to the current time:
			timeout.tv_nsec += 100000000;
			timeout.tv_sec += timeout.tv_nsec / 1000000000;
			timeout.tv_nsec %= 1000000000;
			
			do {
				int result = pthread_cond_timedwait(&_condition, &_mutex, &timeout);
				
				if (result == ETIMEDOUT) {
					pthread_mutex_unlock(&_mutex);
					return false;
				}
			} while (_size == 0);
		}
		
		_size -= 1;
		pthread_mutex_unlock(&_mutex);
		
		return true;
	}
	
	void release() {
		pthread_mutex_lock(&_mutex);
		_size += 1;
		// fprintf(stderr, "T+%ld ResourcePool: Release %d...\n", time_offset_ms(), _size);
		pthread_cond_signal(&_condition);
		pthread_mutex_unlock(&_mutex);
	}
};

class Worker {
	std::string _name;
	ResourcePool& _pool;
	pthread_t _thread;
	
public:
	Worker(std::string name, ResourcePool& pool) : _name(name), _pool(pool) {
		pthread_create(&_thread, NULL, &Worker::_run, this);
	}
	
	~Worker() {
		pthread_join(_thread, NULL);
	}
	
	static void* _run(void* arg) {
		Worker* worker = static_cast<Worker*>(arg);
		worker->run();
		return NULL;
	}
	
	void run() {
		fprintf(stderr, "T+%ld %s: Started\n", time_offset_ms(), _name.c_str());
		
		for (int i = 0; i < 100; ++i) {
			fprintf(stderr, "T+%ld %s: (A) Acquire...\n", time_offset_ms(), _name.c_str());
			if (_pool.acquire()) {
				fprintf(stderr, "T+%ld %s: (A) Acquired!\n", time_offset_ms(), _name.c_str());
				usleep(1000);
				fprintf(stderr, "T+%ld %s: (A) Release...\n", time_offset_ms(), _name.c_str());
				_pool.release();
			} else {
				fprintf(stderr, "T+%ld %s: Timed out!\n", time_offset_ms(), _name.c_str());
			}
			
			fprintf(stderr, "T+%ld %s: (B) Acquire...\n", time_offset_ms(), _name.c_str());
			if (_pool.acquire()) {
				fprintf(stderr, "T+%ld %s: (B) Acquired!\n", time_offset_ms(), _name.c_str());
				usleep(1000);
				fprintf(stderr, "T+%ld %s: (B) Release...\n", time_offset_ms(), _name.c_str());
				_pool.release();
			} else {
				fprintf(stderr, "T+%ld %s: Timed out!\n", time_offset_ms(), _name.c_str());
			}
			
			fprintf(stderr, "T+%ld %s: (C) Work...\n", time_offset_ms(), _name.c_str());
			usleep(10);
		}
	}
};

int main(int argc, const char * argv[]) {
	clock_gettime(CLOCK_REALTIME, &g_start_time);
	
	ResourcePool pool;
	std::vector<Worker> workers;
	
	// Create 3 workers:
	for (int i = 0; i < 3; ++i) {
		std::string name = std::string("worker-") + std::to_string(i);
		workers.emplace_back(name, pool);
	}
	
	// Wait for them to finish:
	workers.clear();
}
