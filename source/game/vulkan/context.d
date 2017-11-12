module game.vulkan.context;

import erupted;

import gl3n.linalg;

import game.vulkan.disposer;

alias PAllocators = const(VkAllocationCallbacks)*;

struct VulkanContext {
	VkInstance instance;
	PAllocators pAllocator;
	VkPhysicalDevice physicalDevice;
	DispatchDevice device;
	VkSwapchainKHR swapChain;
	VkFormat swapChainImageFormat;
	VkExtent2D swapChainExtent;
	VkImage[] swapChainImages;
	VkImageView[] swapChainImageViews;
	VkImage depthImage;
	VkImageView depthImageView;
	VkDeviceMemory depthImageMemory;
	VkFramebuffer[] swapChainFramebuffers;
	VkRenderPass renderPass;
	VkDescriptorSetLayout descriptorSetLayout;
	VkPipelineLayout pipelineLayout;
	VkPipeline graphicsPipeline;
	VkCommandPool commandPool;
	VkCommandBuffer[] commandBuffers;
	VkDescriptorPool descriptorPool;
	VkPhysicalDeviceFeatures deviceFeatures;
	Disposer disposer;
	Disposer swapChainDisposer;

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
