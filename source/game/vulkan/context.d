module game.vulkan.context;

import erupted;

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
	VkPipelineLayout pipelineLayout;
	VkPipeline graphicsPipeline;
	VkCommandPool commandPool;
	VkCommandBuffer[] commandBuffers;

	VkBuffer vertexBuffer;
	VkDeviceMemory vertexBufferMemory;
	VkBuffer indexBuffer;
	VkDeviceMemory indexBufferMemory;

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
