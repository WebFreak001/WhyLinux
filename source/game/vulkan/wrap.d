module game.vulkan.wrap;

import game.vulkan.context;

import erupted;

import std.algorithm;
import std.string;
import std.typecons;

version (Have_derelict_glfw3) {
	import derelict.glfw3.glfw3;

	mixin DerelictGLFW3_VulkanBind;
}
else
	import glfw3d : glfwGetRequiredInstanceExtensions;

struct VulkanVersion {
	uint versionNum;
	alias versionNum this;

	this(uint num) {
		versionNum = num;
	}

	this(uint major, uint minor, uint patch) {
		versionNum = VK_MAKE_VERSION(major, minor, patch);
	}

	uint major() const {
		return VK_VERSION_MAJOR(versionNum);
	}

	uint minor() const {
		return VK_VERSION_MINOR(versionNum);
	}

	uint patch() const {
		return VK_VERSION_PATCH(versionNum);
	}

	enum api1_0 = VulkanVersion(VK_API_VERSION_1_0);
}

struct ApplicationInfo {
	VkApplicationInfo info;
	alias info this;

	string applicationName() const {
		return info.pApplicationName.fromStringz.idup;
	}

	string applicationName(string newName) {
		info.pApplicationName = newName.toStringz;
		return newName;
	}

	VulkanVersion applicationVersion() const {
		return VulkanVersion(info.applicationVersion);
	}

	VulkanVersion applicationVersion(VulkanVersion newVersion) {
		info.applicationVersion = newVersion.versionNum;
		return newVersion;
	}

	string engineName() const {
		return info.pEngineName.fromStringz.idup;
	}

	string engineName(string newName) {
		info.pEngineName = newName.toStringz;
		return newName;
	}

	VulkanVersion engineVersion() const {
		return VulkanVersion(info.engineVersion);
	}

	VulkanVersion engineVersion(VulkanVersion newVersion) {
		info.engineVersion = newVersion.versionNum;
		return newVersion;
	}

	VulkanVersion apiVersion() const {
		return VulkanVersion(info.apiVersion);
	}

	VulkanVersion apiVersion(VulkanVersion newVersion) {
		info.apiVersion = newVersion.versionNum;
		return newVersion;
	}
}

void fillRequiredInstanceExtensions(ref VkInstanceCreateInfo info, bool validate = true) {
	import std.stdio : stderr;
	import core.stdc.string : strcmp;

	info.ppEnabledExtensionNames = glfwGetRequiredInstanceExtensions(&info.enabledExtensionCount);

	if (validate) {
		uint count;
		vkEnumerateInstanceExtensionProperties(null, &count, null);
		VkExtensionProperties[] props = new VkExtensionProperties[count];
		vkEnumerateInstanceExtensionProperties(null, &count, props.ptr);
		foreach (requiredExtension; info.ppEnabledExtensionNames[0 .. info.enabledExtensionCount]) {
			if (!props.canFind!(a => strcmp(a.extensionName.ptr, requiredExtension) == 0))
				stderr.writefln("Warning: Required Vulkan Extension '%s' missing in vkEnumerateInstanceExtensionProperties",
						requiredExtension.fromStringz);
		}
	}
}

VkResult enforceVK(VkResult result, lazy string what = "Vulkan operation") {
	import std.conv : to;

	if (result != VkResult.VK_SUCCESS)
		throw new Exception(what ~ " failed with " ~ result.to!string);

	return result;
}

auto findQueueFamilies(vkQueueFlagBits...)(VkPhysicalDevice device, VkSurfaceKHR surface)
in {
	assert(device);
	assert(surface);
}
body {
	enum FlagBitsOffset = 1;
	mixin({
		string code = `Tuple!(int,"present",`;
		foreach (bit; vkQueueFlagBits) {
			code ~= `int,`;
			final switch (cast(VkQueueFlagBits) bit) {
			case VkQueueFlagBits.VK_QUEUE_COMPUTE_BIT:
				code ~= `"compute",`;
				break;
			case VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT:
				code ~= `"graphics",`;
				break;
			case VkQueueFlagBits.VK_QUEUE_SPARSE_BINDING_BIT:
				code ~= `"sparseBinding",`;
				break;
			case VkQueueFlagBits.VK_QUEUE_TRANSFER_BIT:
				code ~= `"transfer",`;
				break;
			case VkQueueFlagBits.VK_QUEUE_FLAG_BITS_MAX_ENUM:
				assert(false,
					"Passed VK_QUEUE_FLAG_BITS_MAX_ENUM as findQueueFamilies bit");
			}
		}
		return code ~ ") ret;";
	}());

	uint queueFamilyCount;
	vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
	VkQueueFamilyProperties[] queueFamilies = new VkQueueFamilyProperties[queueFamilyCount];
	vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);

	foreach (i, ref family; queueFamilies) {
		if (family.queueCount > 0) {
			VkBool32 presentSupport;
			vkGetPhysicalDeviceSurfaceSupportKHR(device, cast(uint) i, surface, &presentSupport);
			if (presentSupport)
				ret.present = cast(int) i;
			foreach (n, bit; vkQueueFlagBits) {
				if (family.queueFlags & bit)
					ret[n + FlagBitsOffset] = cast(int) i;
			}
		}
	}

	return ret;
}

/// Returns: true if all extensions are present
bool checkDeviceExtensions(VkPhysicalDevice device, string[] extensions) {
	uint count;
	vkEnumerateDeviceExtensionProperties(device, null, &count, null);
	VkExtensionProperties[] props = new VkExtensionProperties[count];
	vkEnumerateDeviceExtensionProperties(device, null, &count, props.ptr);

	foreach (i, string ext; extensions) {
		if (!props.canFind!(a => a.extensionName.ptr.fromStringz == ext))
			return false;
	}

	return true;
}

struct SwapChainSupportDetails {
	VkSurfaceCapabilitiesKHR capabilities;
	VkSurfaceFormatKHR[] formats;
	VkPresentModeKHR[] presentModes;
}

SwapChainSupportDetails querySwapChainSupport(VkPhysicalDevice device, VkSurfaceKHR surface) {
	SwapChainSupportDetails details;

	vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities);

	uint formatCount;
	vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, null);
	details.formats.length = formatCount;
	if (formatCount)
		vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, details.formats.ptr);

	uint presentModeCount;
	vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, null);
	details.presentModes.length = presentModeCount;
	if (presentModeCount)
		vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface,
				&presentModeCount, details.presentModes.ptr);

	return details;
}

VkSurfaceFormatKHR chooseOptimalSwapSurfaceFormat(ref VkSurfaceFormatKHR[] available,
		VkFormat format, VkColorSpaceKHR colorspace = VkColorSpaceKHR.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
	if (available.length == 1 && available[0].format == VK_FORMAT_UNDEFINED)
		return VkSurfaceFormatKHR(format, colorspace);

	foreach (ref fmt; available) {
		if (fmt.format == format && fmt.colorSpace == colorspace)
			return fmt;
	}

	foreach (ref fmt; available) {
		if (fmt.format == format)
			return fmt;
	}

	return available[0];
}

VkPresentModeKHR chooseSwapPresentMode(ref VkPresentModeKHR[] available) {
	VkPresentModeKHR best = VK_PRESENT_MODE_FIFO_KHR;

	foreach (ref mode; available) {
		if (mode == VK_PRESENT_MODE_MAILBOX_KHR)
			return mode;
		else if (mode == VK_PRESENT_MODE_IMMEDIATE_KHR)
			best = mode;
	}

	return best;
}

VkExtent2D chooseSwapExtent(in ref VkSurfaceCapabilitiesKHR capabilities, int width, int height) {
	if (capabilities.currentExtent.width != uint.max)
		return capabilities.currentExtent;
	else {
		VkExtent2D actualExtent;
		actualExtent.width = width;
		actualExtent.height = height;

		actualExtent.width = clamp(actualExtent.width,
				capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
		actualExtent.height = clamp(actualExtent.height,
				capabilities.minImageExtent.height, capabilities.maxImageExtent.height);

		return actualExtent;
	}
}

uint findMemoryType(VkPhysicalDevice device, uint typeFilter, VkMemoryPropertyFlags properties) {
	VkPhysicalDeviceMemoryProperties memProperties;
	vkGetPhysicalDeviceMemoryProperties(device, &memProperties);

	for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
		if ((typeFilter & (1 << i))
				&& (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
			return i;
		}
	}

	throw new Exception("Failed to find suitable memory type");
}

void createBuffer(ref VulkanContext context, VkDeviceSize size, VkBufferUsageFlags usage,
		VkMemoryPropertyFlags properties, ref VkBuffer buffer, ref VkDeviceMemory bufferMemory) {
	VkBufferCreateInfo bufferInfo;
	bufferInfo.size = size;
	bufferInfo.usage = usage;
	bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

	context.device.CreateBuffer(&bufferInfo, context.pAllocator, &buffer)
		.enforceVK("vkCreateBuffer");

	VkMemoryRequirements memRequirements;
	context.device.GetBufferMemoryRequirements(buffer, &memRequirements);

	VkMemoryAllocateInfo allocInfo;
	allocInfo.allocationSize = memRequirements.size;
	allocInfo.memoryTypeIndex = findMemoryType(context.physicalDevice,
			memRequirements.memoryTypeBits, properties);

	context.device.AllocateMemory(&allocInfo, context.pAllocator,
			&bufferMemory).enforceVK("vkAllocateMemory");

	context.device.BindBufferMemory(buffer, bufferMemory, 0);
}

void copyBufferSync(ref VulkanContext context, VkBuffer src, VkBuffer dst,
		VkDeviceSize size, VkDeviceSize srcOffset = 0, VkDeviceSize dstOffset = 0) {
	VkCommandBufferAllocateInfo allocInfo;
	allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	allocInfo.commandPool = context.commandPool;
	allocInfo.commandBufferCount = 1;

	VkCommandBuffer commandBuffer;
	context.device.AllocateCommandBuffers(&allocInfo, &commandBuffer);

	VkCommandBufferBeginInfo beginInfo;
	beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

	context.device.vkBeginCommandBuffer(commandBuffer, &beginInfo);
	scope (exit)
		context.device.FreeCommandBuffers(context.commandPool, 1, &commandBuffer);

	VkBufferCopy copyRegion;
	copyRegion.srcOffset = srcOffset;
	copyRegion.dstOffset = dstOffset;
	copyRegion.size = size;
	context.device.vkCmdCopyBuffer(commandBuffer, src, dst, 1, &copyRegion);

	context.device.vkEndCommandBuffer(commandBuffer);

	VkSubmitInfo submitInfo;
	submitInfo.commandBufferCount = 1;
	submitInfo.pCommandBuffers = &commandBuffer;

	context.device.vkQueueSubmit(context.graphicsQueue, 1, &submitInfo, VK_NULL_ND_HANDLE);
	context.device.vkQueueWaitIdle(context.graphicsQueue);
}
