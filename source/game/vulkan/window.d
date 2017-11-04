module game.vulkan.window;

import erupted;

import glfw3d;

import game.vulkan.wrap;

import std.conv;

/// Callback for rating a device. Return <=0 if unsuitable
alias DeviceScoreFn = int function(VkSurfaceKHR, VkPhysicalDevice,
		VkPhysicalDeviceProperties, VkPhysicalDeviceFeatures);

int wrapRate(alias fn)(VkPhysicalDevice device, VkSurfaceKHR surface) {
	VkPhysicalDeviceProperties props;
	VkPhysicalDeviceFeatures features;

	vkGetPhysicalDeviceProperties(device, &props);
	vkGetPhysicalDeviceFeatures(device, &features);

	return fn(surface, device, props, features);
}

class VulkanWindow : Window {
	VkInstance instance;
	const(VkAllocationCallbacks)* pAllocator;
	VkPhysicalDevice physicalDevice;
	VkDevice device;
	VkSwapchainKHR swapChain;
	VkFormat swapChainImageFormat;
	VkExtent2D swapChainExtent;
	VkImage[] swapChainImages;
	VkImageView[] swapChainImageViews;

	VkQueue presentQueue;
	VkQueue computeQueue;
	VkQueue graphicsQueue;
	VkQueue sparseBindingQueue;
	VkQueue transferQueue;

	uint presentIndex = uint.max;
	uint computeIndex = uint.max;
	uint graphicsIndex = uint.max;
	uint sparseBindingIndex = uint.max;
	uint transferIndex = uint.max;

	VkSurfaceKHR surface;

	this(int width, int height, string name) {
		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
		super(width, height, name);
	}

	override void destroy() {
		foreach (ref view; swapChainImageViews)
			vkDestroyImageView(device, view, pAllocator);

		if (swapChain)
			vkDestroySwapchainKHR(device, swapChain, pAllocator);

		if (surface)
			vkDestroySurfaceKHR(instance, surface, pAllocator);

		if (device)
			vkDestroyDevice(device, pAllocator);

		if (instance)
			vkDestroyInstance(instance, pAllocator);

		super.destroy();
	}

	void createSurface() {
		glfwCreateWindowSurface(instance, ptr, pAllocator, &surface).enforceVK(
				"glfwCreateWindowSurface");
	}

	void createInstance(const(VkInstanceCreateInfo)* pCreateInfo)
	in {
		assert(pCreateInfo);
	}
	body {
		vkCreateInstance(pCreateInfo, pAllocator, &instance).enforceVK("vkCreateInstance");
		loadInstanceLevelFunctions(instance);
	}

	void selectPhysicalDevice(alias rateDevice)() {
		import std.algorithm : maxElement;

		assert(instance);
		assert(vkEnumeratePhysicalDevices);

		uint deviceCount;
		vkEnumeratePhysicalDevices(instance, &deviceCount, null);
		VkPhysicalDevice[] devices = new VkPhysicalDevice[deviceCount];
		vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr);

		if (deviceCount == 0)
			throw new Exception("No GPU with vulkan support found");

		auto picked = devices.maxElement!(a => a.wrapRate!rateDevice(surface));

		if (wrapRate!rateDevice(picked, surface) <= 0)
			throw new Exception("No suitable GPU found");

		physicalDevice = picked;
	}

	void createLogicalDevice(vkQueueFlagBits...)(auto ref VkDeviceCreateInfo createInfoBase) {
		auto indices = physicalDevice.findQueueFamilies!vkQueueFlagBits(surface);

		VkDeviceQueueCreateInfo[indices.expand.length] queueCreateInfos;
		float queuePriority = 1;
		foreach (i, index; indices) {
			queueCreateInfos[i].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
			queueCreateInfos[i].queueFamilyIndex = index;
			queueCreateInfos[i].queueCount = 1;
			queueCreateInfos[i].pQueuePriorities = &queuePriority;
		}

		createInfoBase.pQueueCreateInfos = queueCreateInfos.ptr;
		createInfoBase.queueCreateInfoCount = queueCreateInfos.length;

		vkCreateDevice(physicalDevice, &createInfoBase, pAllocator, &device).enforceVK(
				"vkCreateDevice");

		loadDeviceLevelFunctions(device);

		vkGetDeviceQueue(device, indices.present, 0, &presentQueue);
		presentIndex = indices.present;
		foreach (bit; vkQueueFlagBits) {
			static if (bit == VkQueueFlagBits.VK_QUEUE_COMPUTE_BIT) {
				vkGetDeviceQueue(device, indices.compute, 0, &computeQueue);
				computeIndex = indices.compute;
			}
			else static if (bit == VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT) {
				vkGetDeviceQueue(device, indices.graphics, 0, &graphicsQueue);
				graphicsIndex = indices.graphics;
			}
			else static if (bit == VkQueueFlagBits.VK_QUEUE_SPARSE_BINDING_BIT) {
				vkGetDeviceQueue(device, indices.sparseBinding, 0, &sparseBindingQueue);
				sparseBindingIndex = indices.sparseBinding;
			}
			else static if (bit == VkQueueFlagBits.VK_QUEUE_TRANSFER_BIT) {
				vkGetDeviceQueue(device, indices.transfer, 0, &transferQueue);
				transferIndex = indices.transfer;
			}
			else
				static assert(false, "Invalid queue bit passed");
		}
	}

	void createSwapChain() {
		SwapChainSupportDetails swapChainSupport = querySwapChainSupport(physicalDevice, surface);

		VkSurfaceFormatKHR surfaceFormat = swapChainSupport.formats.chooseOptimalSwapSurfaceFormat(
				VK_FORMAT_B8G8R8A8_UNORM);
		VkPresentModeKHR presentMode = swapChainSupport.presentModes.chooseSwapPresentMode;
		auto size = getSize();
		VkExtent2D extent = swapChainSupport.capabilities.chooseSwapExtent(size.width, size.height);

		uint imageCount = swapChainSupport.capabilities.minImageCount + 1;
		if (swapChainSupport.capabilities.maxImageCount > 0
				&& imageCount > swapChainSupport.capabilities.maxImageCount)
			imageCount = swapChainSupport.capabilities.maxImageCount;

		VkSwapchainCreateInfoKHR createInfo;
		createInfo.surface = surface;

		createInfo.minImageCount = imageCount;
		createInfo.imageFormat = surfaceFormat.format;
		createInfo.imageColorSpace = surfaceFormat.colorSpace;
		createInfo.imageExtent = extent;
		createInfo.imageArrayLayers = 1; // change to 2 for stereographic 3D
		createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

		assert(graphicsIndex != uint.max);
		assert(presentIndex != uint.max);

		uint[2] queueFamilyIndices = [graphicsIndex, presentIndex];
		if (graphicsIndex == presentIndex) {
			createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
			createInfo.queueFamilyIndexCount = 2;
			createInfo.pQueueFamilyIndices = queueFamilyIndices.ptr;
		}
		else
			createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;

		createInfo.preTransform = swapChainSupport.capabilities.currentTransform;
		createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR; // change to make window transparent
		createInfo.presentMode = presentMode;
		createInfo.clipped = VK_TRUE; // change to false for screenshots
		createInfo.oldSwapchain = null; // TODO: for recreation of swapchain

		vkCreateSwapchainKHR(device, &createInfo, pAllocator, &swapChain).enforceVK(
				"vkCreateSwapchainKHR");

		imageCount = 0;
		vkGetSwapchainImagesKHR(device, swapChain, &imageCount, null);
		swapChainImages.length = imageCount;
		vkGetSwapchainImagesKHR(device, swapChain, &imageCount, swapChainImages.ptr);

		swapChainImageFormat = surfaceFormat.format;
		swapChainExtent = extent;
	}

	void createImageViews() {
		swapChainImageViews.length = swapChainImages.length;

		foreach (i, ref image; swapChainImages) {
			VkImageViewCreateInfo createInfo;
			createInfo.image = image;
			createInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
			createInfo.format = swapChainImageFormat;

			createInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
			createInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
			createInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
			createInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY; // maybe put one here?

			createInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT; // create multiple layers for stereographic 3D
			createInfo.subresourceRange.baseMipLevel = 0;
			createInfo.subresourceRange.levelCount = 1;
			createInfo.subresourceRange.baseArrayLayer = 0;
			createInfo.subresourceRange.layerCount = 1;

			vkCreateImageView(device, &createInfo, pAllocator, &swapChainImageViews[i]).enforceVK(
					"vkCreateImageView #" ~ i.to!string);
		}
	}
}
