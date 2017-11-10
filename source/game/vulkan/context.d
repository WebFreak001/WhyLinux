module game.vulkan.context;

import erupted;

import gl3n.linalg;

struct VulkanContext {
	VkInstance instance;
	const(VkAllocationCallbacks)* pAllocator;
	VkPhysicalDevice physicalDevice;
	DispatchDevice device;
	VkSwapchainKHR swapChain;
	VkFormat swapChainImageFormat;
	VkExtent2D swapChainExtent;
	VkImage[] swapChainImages;
	VkImageView[] swapChainImageViews;
	VkFramebuffer[] swapChainFramebuffers;
	VkRenderPass renderPass;
	VkDescriptorSetLayout descriptorSetLayout;
	VkPipelineLayout pipelineLayout;
	VkPipeline graphicsPipeline;
	VkCommandPool commandPool;
	VkCommandBuffer[] commandBuffers;
	VkDescriptorPool descriptorPool;
	VkDescriptorSet descriptorSet;
	VkPhysicalDeviceFeatures deviceFeatures;

	VkBuffer meshBuffer;
	VkDeviceMemory meshBufferMemory;
	VkBuffer uniformBuffer;
	VkDeviceMemory uniformBufferMemory;
	VkImage textureImage;
	VkImageView textureImageView;
	VkSampler textureSampler;
	VkDeviceMemory textureImageMemory;

	VkSemaphore imageAvailableSemaphore;
	VkSemaphore renderFinishedSemaphore;

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
}

struct UniformBufferObject {
	// keep in sync with shaders
	mat4 model, view, projection;
}
