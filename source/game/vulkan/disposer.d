module game.vulkan.disposer;

import erupted;

import game.vulkan.context;

import std.functional : toDelegate;
import std.traits : isCallable, isArray;

struct Disposer {
	void delegate()[] callbacks;
	VulkanContext* context;

	this(ref VulkanContext context) {
		this.context = &context;
	}

	void dispose() {
		foreach_reverse (cb; callbacks)
			cb();
		callbacks.length = 0;
	}

	void register(T)(T o) if (is(typeof(T.init.destroy) : void delegate())) {
		callbacks ~= &o.destroy;
	}

	void register(T)(T o) if (is(typeof(T.init.destroy) : void function())) {
		callbacks ~= toDelegate(&o.destroy);
	}

	void register(void delegate() destroy) {
		callbacks ~= destroy;
	}

	void register(void function() destroy) {
		callbacks ~= toDelegate(destroy);
	}

	void register(string method, T)(T[] os) {
		callbacks ~= () {
			foreach (ref o; os)
				mixin("context.device." ~ method)(o, context.pAllocator);
		};
	}

	void register(string method, T)(T o) if (!isArray!T) {
		callbacks ~= () { mixin("context.device." ~ method)(o, context.pAllocator); };
	}

	void register(alias fn, Args...)(Args args) if (isCallable!fn) {
		callbacks ~= () { fn(args); };
	}

	void register(VkBuffer buffer, VkDeviceMemory memory) {
		callbacks ~= () {
			context.device.DestroyBuffer(buffer, context.pAllocator);
			context.device.FreeMemory(memory, context.pAllocator);
		};
	}

	void register(VkImage image, VkDeviceMemory memory) {
		callbacks ~= () {
			context.device.DestroyImage(image, context.pAllocator);
			context.device.FreeMemory(memory, context.pAllocator);
		};
	}
}
