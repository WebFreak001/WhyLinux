module game.vulkan.window;

import erupted;

import glfw3d;

import game.vulkan.wrap;

class VulkanWindow : Window {
	VkInstance instance;
	const(VkAllocationCallbacks)* pAllocator;

	this(int width, int height, string name) {
		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
		super(width, height, name);
	}

	override void destroy() {
		vkDestroyInstance(instance, pAllocator);

		super.destroy();
	}

	void createInstance(const(VkInstanceCreateInfo)* pCreateInfo) {
		vkCreateInstance(pCreateInfo, pAllocator, &instance).enforceVK("vkCreateInstance");
	}
}
