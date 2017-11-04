module game.vulkan.wrap;

import erupted;

import std.string;

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
	import glfw3d : glfwGetRequiredInstanceExtensions;
	import std.algorithm : canFind;
	import std.stdio : stderr;
	import core.stdc.string : strcmp;

	info.ppEnabledExtensionNames = glfwGetRequiredInstanceExtensions(&info.enabledExtensionCount);

	if (validate) {
		uint count;
		vkEnumerateInstanceExtensionProperties(null, &count, null);
		VkExtensionProperties[] props = new VkExtensionProperties[count];
		vkEnumerateInstanceExtensionProperties(null, &count, props.ptr);
		foreach (requiredExtension; info.ppEnabledExtensionNames[0 .. info.enabledExtensionCount]) {
			if (!props.canFind!(a => strcmp(a.extensionName.ptr, requiredExtension)))
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
