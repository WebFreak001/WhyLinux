import std.stdio;
import std.math;
import std.string;

import erupted;

import glfw3d;

import game.vulkan.wrap;
import game.vulkan.window;

static string[] deviceExtensions = [VK_KHR_SWAPCHAIN_EXTENSION_NAME];

void main() {
	DerelictErupted.load();

	glfw3dInit();
	scope (exit)
		glfw3dTerminate();

	VulkanWindow w = new VulkanWindow(853, 600, "WhyLinux");

	w.setUserPointer(cast(void*) cast(Window) w);
	w.setSizeCallback(&onWindowResized);

	{
		ApplicationInfo appInfo;
		appInfo.applicationName = "WhyLinux";
		appInfo.applicationVersion = VulkanVersion(1, 0, 0);
		appInfo.engineName = "WhyLinuxEngine";
		appInfo.engineVersion = VulkanVersion(0, 1, 0);
		appInfo.apiVersion = VulkanVersion.api1_0;

		VkInstanceCreateInfo createInfo;
		createInfo.pApplicationInfo = &appInfo.info;

		createInfo.fillRequiredInstanceExtensions();

		createInfo.enabledLayerCount = 0;

		w.createInstance(&createInfo);
	}

	w.createSurface();
	w.selectPhysicalDevice!rateDevice;

	VkDeviceCreateInfo createInfo;

	VkPhysicalDeviceFeatures deviceFeatures;
	createInfo.pEnabledFeatures = &deviceFeatures;

	createInfo.enabledExtensionCount = cast(uint) deviceExtensions.length;
	createInfo.ppEnabledExtensionNames = deviceExtensions.toStringzz;
	w.createLogicalDevice!(VK_QUEUE_GRAPHICS_BIT)(createInfo);

	w.createSwapChain();
	w.createImageViews();

	w.createRenderPass();
	w.createGraphicsPipeline();

	w.createFramebuffers();

	w.createCommandPool();

	w.createVertexBuffer();

	w.createCommandBuffers();
	w.createSemaphores();

	stderr.writeln("Successfully created vulkan context");

	while (!w.shouldClose()) {
		glfwPollEvents();
		w.drawFrame();
	}
}

extern (C) nothrow void onWindowResized(GLFWwindow* window, int width, int height) {
	if (width == 0 || height == 0)
		return;

	auto w = cast(VulkanWindow) glfwGetWindowUserPointer(window);
	try {
		w.recreateSwapChain();
	}
	catch (Exception e) {
		assert(false);
	}
}

int rateDevice(VkSurfaceKHR surface, VkPhysicalDevice device,
		VkPhysicalDeviceProperties props, VkPhysicalDeviceFeatures) {
	int score = 1;
	if (props.deviceType == VkPhysicalDeviceType.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU)
		score += 1000;
	else if (props.deviceType == VkPhysicalDeviceType.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
			|| props.deviceType == VkPhysicalDeviceType.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU)
		score += 100;

	// TODO: check props limits according to game & rate gpu accordingly

	// TODO: check features according to game

	auto queues = device.findQueueFamilies!(VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT,
			VkQueueFlagBits.VK_QUEUE_TRANSFER_BIT)(surface);

	if (queues.graphics < 0)
		return 0;

	if (!device.checkDeviceExtensions(deviceExtensions))
		return 0;

	auto swapChainSupport = querySwapChainSupport(device, surface);
	if (!swapChainSupport.formats.length)
		return 0;
	if (!swapChainSupport.presentModes.length)
		return 0;

	return score;
}

immutable(char)** toStringzz(string[] arr) {
	immutable(char)*[] ret;
	foreach (a; arr)
		ret ~= a.toStringz;
	return ret.ptr;
}
