module game.vulkan.shader;

import erupted;

import std.file : readFile = read;

import game.vulkan.context;
import game.vulkan.wrap;

VkShaderModule createShaderModule(ref VulkanContext context, in ubyte[] code, in string origin) {
	VkShaderModuleCreateInfo createInfo;
	createInfo.codeSize = cast(uint) code.length;
	createInfo.pCode = cast(uint*) code.ptr;

	VkShaderModule shaderModule;

	vkCreateShaderModule(context.device, &createInfo, context.pAllocator, &shaderModule).enforceVK(
			"vkCreateShaderModule with file " ~ origin);

	return shaderModule;
}

VkShaderModule createShaderModule(ref VulkanContext context, in char[] file) {
	return createShaderModule(context, cast(ubyte[]) readFile(file), file.idup);
}
