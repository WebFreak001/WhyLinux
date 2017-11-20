module game.vulkan.wrap;

import game.vulkan.context;

import erupted;

import std.algorithm;
import std.string;
import std.typecons;
import std.traits;

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

void createTransferSrcBuffer(ref VulkanContext context, VkDeviceSize size,
		ref VkBuffer buffer, ref VkDeviceMemory bufferMemory) {
	createBuffer(context, size, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
			VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
			buffer, bufferMemory);
}

VkCommandBuffer beginSingleTimeCommands(ref VulkanContext context) {
	VkCommandBufferAllocateInfo allocInfo;
	allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	allocInfo.commandPool = context.commandPool;
	allocInfo.commandBufferCount = 1;

	VkCommandBuffer commandBuffer;
	context.device.AllocateCommandBuffers(&allocInfo, &commandBuffer);

	VkCommandBufferBeginInfo beginInfo;
	beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

	context.device.vkBeginCommandBuffer(commandBuffer, &beginInfo);

	return commandBuffer;
}

void endSingleTimeCommands(ref VulkanContext context, ref VkCommandBuffer commandBuffer) {
	context.device.vkEndCommandBuffer(commandBuffer);

	VkSubmitInfo submitInfo;
	submitInfo.commandBufferCount = 1;
	submitInfo.pCommandBuffers = &commandBuffer;

	context.device.vkQueueSubmit(context.graphicsQueue, 1, &submitInfo, VK_NULL_ND_HANDLE);
	context.device.vkQueueWaitIdle(context.graphicsQueue);

	context.device.FreeCommandBuffers(context.commandPool, 1, &commandBuffer);
}

void copyBufferSync(ref VulkanContext context, VkBuffer src, VkBuffer dst,
		VkDeviceSize size, VkDeviceSize srcOffset = 0, VkDeviceSize dstOffset = 0) {
	auto commandBuffer = context.beginSingleTimeCommands();
	scope (exit)
		context.endSingleTimeCommands(commandBuffer);

	VkBufferCopy copyRegion;
	copyRegion.srcOffset = srcOffset;
	copyRegion.dstOffset = dstOffset;
	copyRegion.size = size;
	context.device.vkCmdCopyBuffer(commandBuffer, src, dst, 1, &copyRegion);
}

void transitionImageLayout(ref VulkanContext context, VkImage image,
		VkFormat format, VkImageLayout oldLayout, VkImageLayout newLayout) {
	auto commandBuffer = context.beginSingleTimeCommands();
	scope (exit)
		context.endSingleTimeCommands(commandBuffer);

	VkImageMemoryBarrier barrier;
	barrier.oldLayout = oldLayout;
	barrier.newLayout = newLayout;
	barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	barrier.image = image;
	if (newLayout == VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
		barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
		if (format.hasStencilComponent)
			barrier.subresourceRange.aspectMask |= VK_IMAGE_ASPECT_STENCIL_BIT;
	}
	else
		barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	barrier.subresourceRange.baseMipLevel = 0;
	barrier.subresourceRange.levelCount = 1;
	barrier.subresourceRange.baseArrayLayer = 0;
	barrier.subresourceRange.layerCount = 1;

	VkPipelineStageFlags sourceStage;
	VkPipelineStageFlags destinationStage;

	if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && newLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
		barrier.srcAccessMask = 0;
		barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

		sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
		destinationStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
	}
	else if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED
			&& newLayout == VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
		barrier.srcAccessMask = 0;
		barrier.dstAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT
			| VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

		sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
		destinationStage = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
	}
	else if (oldLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
			&& newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
		barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
		barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

		sourceStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
		destinationStage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
	}
	else
		throw new Exception("Invalid transition arguments");

	context.device.vkCmdPipelineBarrier(commandBuffer, sourceStage,
			destinationStage, 0, 0, null, 0, null, 1, &barrier);
}

void copyBufferToImage(ref VulkanContext context, VkBuffer buffer, VkImage image,
		uint width, uint height, VkDeviceSize bufferOffset = 0) {
	auto commandBuffer = context.beginSingleTimeCommands();
	scope (exit)
		context.endSingleTimeCommands(commandBuffer);

	VkBufferImageCopy region;
	region.bufferOffset = bufferOffset;
	region.bufferRowLength = 0;
	region.bufferImageHeight = 0;

	region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	region.imageSubresource.mipLevel = 0;
	region.imageSubresource.baseArrayLayer = 0;
	region.imageSubresource.layerCount = 1;

	region.imageOffset = VkOffset3D(0, 0, 0);
	region.imageExtent = VkExtent3D(width, height, 1);

	context.device.vkCmdCopyBufferToImage(commandBuffer, buffer, image,
			VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
}

void fillGPUMemory(alias fn)(ref VulkanContext context, VkDeviceMemory memory,
		VkDeviceSize size, VkDeviceSize offset = 0) {
	void* data;
	context.device.MapMemory(memory, offset, size, 0, &data);
	fn(data[0 .. size]);
	context.device.UnmapMemory(memory);
}

void fillGPUMemory(ref VulkanContext context, VkDeviceMemory memory,
		VkDeviceSize offset, void[] data) {
	void* gpu;
	context.device.MapMemory(memory, offset, cast(VkDeviceSize) data.length, 0, &gpu);
	gpu[0 .. data.length] = data;
	context.device.UnmapMemory(memory);
}

void fillGPUMemory(T)(ref VulkanContext context, VkDeviceMemory memory, VkDeviceSize offset, T data)
		if (!isDynamicArray!T) {
	void* gpu;
	context.device.MapMemory(memory, offset, cast(VkDeviceSize) T.sizeof, 0, &gpu);
	*(cast(T*) gpu) = data;
	context.device.UnmapMemory(memory);
}

void createImage(ref VulkanContext context, uint width, uint height,
		VkFormat format, VkImageTiling tiling, VkImageUsageFlags usage,
		VkMemoryPropertyFlags properties, ref VkImage image, ref VkDeviceMemory imageMemory) {
	VkImageCreateInfo imageInfo;
	imageInfo.imageType = VK_IMAGE_TYPE_2D;
	imageInfo.extent.width = width;
	imageInfo.extent.height = height;
	imageInfo.extent.depth = 1;
	imageInfo.mipLevels = 1;
	imageInfo.arrayLayers = 1;
	imageInfo.format = format;
	imageInfo.tiling = tiling;
	imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
	imageInfo.usage = usage;
	imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
	imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;

	context.device.CreateImage(&imageInfo, context.pAllocator, &image).enforceVK("vkCreateImage");

	VkMemoryRequirements memRequirements;
	context.device.GetImageMemoryRequirements(image, &memRequirements);

	VkMemoryAllocateInfo allocInfo;
	allocInfo.allocationSize = memRequirements.size;
	allocInfo.memoryTypeIndex = findMemoryType(context.physicalDevice,
			memRequirements.memoryTypeBits, properties);

	context.device.AllocateMemory(&allocInfo, context.pAllocator, &imageMemory)
		.enforceVK("vkAllocateMemory");

	context.device.BindImageMemory(image, imageMemory, 0);
}

VkImageView createImageView(ref VulkanContext context, VkImage image,
		VkFormat format, VkImageAspectFlags aspectFlags = VK_IMAGE_ASPECT_COLOR_BIT) {
	VkImageViewCreateInfo viewInfo;
	viewInfo.image = image;
	viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
	viewInfo.format = format;

	viewInfo.subresourceRange.aspectMask = aspectFlags;
	viewInfo.subresourceRange.baseMipLevel = 0;
	viewInfo.subresourceRange.levelCount = 1;
	viewInfo.subresourceRange.baseArrayLayer = 0;
	viewInfo.subresourceRange.layerCount = 1;

	VkImageView imageView;
	context.device.CreateImageView(&viewInfo, context.pAllocator, &imageView)
		.enforceVK("vkCreateImageView");

	return imageView;
}

VkFormat findSupportedFormat(ref VulkanContext context, VkFormat[] candidates,
		VkImageTiling tiling, VkFormatFeatureFlags features) {
	foreach (format; candidates) {
		VkFormatProperties props;
		vkGetPhysicalDeviceFormatProperties(context.physicalDevice, format, &props);
		if (tiling == VK_IMAGE_TILING_LINEAR && (props.linearTilingFeatures & features) == features)
			return format;
		else if (tiling == VK_IMAGE_TILING_OPTIMAL && (props.optimalTilingFeatures & features) == features)
			return format;
	}

	throw new Exception("Failed to find supported format");
}

VkFormat findDepthFormat(ref VulkanContext context) {
	return context.findSupportedFormat([VK_FORMAT_D32_SFLOAT, VK_FORMAT_D32_SFLOAT_S8_UINT,
			VK_FORMAT_D24_UNORM_S8_UINT], VK_IMAGE_TILING_OPTIMAL,
			VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT);
}

bool hasStencilComponent(VkFormat format) {
	return format == VK_FORMAT_D32_SFLOAT_S8_UINT || format == VK_FORMAT_D24_UNORM_S8_UINT;
}

VkSamplerCreateInfo hqSamplerInfo(ref VulkanContext context) {
	VkSamplerCreateInfo samplerInfo;
	samplerInfo.magFilter = VK_FILTER_LINEAR;
	samplerInfo.minFilter = VK_FILTER_LINEAR;
	samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT;
	samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT;
	samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
	if (context.deviceFeatures.samplerAnisotropy) {
		samplerInfo.anisotropyEnable = VK_TRUE;
		samplerInfo.maxAnisotropy = 16;
	}
	else {
		samplerInfo.anisotropyEnable = VK_FALSE;
		samplerInfo.maxAnisotropy = 1;
	}
	samplerInfo.borderColor = VK_BORDER_COLOR_INT_OPAQUE_BLACK;
	samplerInfo.unnormalizedCoordinates = VK_FALSE;
	samplerInfo.compareEnable = VK_FALSE;
	samplerInfo.compareOp = VK_COMPARE_OP_ALWAYS;
	samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
	samplerInfo.mipLodBias = 0.0f;
	samplerInfo.minLod = 0.0f;
	samplerInfo.maxLod = 1000.0f;
	return samplerInfo;
}
