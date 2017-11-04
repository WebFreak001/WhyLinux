module game.vulkan.window;

import erupted;

import glfw3d;

import game.vulkan.context;
import game.vulkan.shader;
import game.vulkan.wrap;

import std.conv;
import std.file : readFile = read;

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
	VulkanContext context;
	alias context this;

	this(int width, int height, string name) {
		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
		super(width, height, name);
	}

	override void destroy() {
		if (commandPool)
			device.DestroyCommandPool(commandPool, pAllocator);

		foreach (ref fb; swapChainFramebuffers)
			device.DestroyFramebuffer(fb, pAllocator);

		if (graphicsPipeline)
			device.DestroyPipeline(graphicsPipeline, pAllocator);

		if (pipelineLayout)
			device.DestroyPipelineLayout(pipelineLayout, pAllocator);

		if (renderPass)
			device.DestroyRenderPass(renderPass, pAllocator);

		foreach (ref view; swapChainImageViews)
			device.DestroyImageView(view, pAllocator);

		if (swapChain)
			device.vkDestroySwapchainKHR(device.vkDevice, swapChain, pAllocator);

		if (surface)
			vkDestroySurfaceKHR(instance, surface, pAllocator);

		if (device != DispatchDevice.init)
			device.DestroyDevice(pAllocator);

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

		auto picked = devices.maxElement!(a => a.wrapRate!rateDevice(context.surface));

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

		VkDevice vkdev;
		vkCreateDevice(physicalDevice, &createInfoBase, pAllocator, &vkdev).enforceVK("vkCreateDevice");

		device.loadDeviceLevelFunctions(vkdev);

		device.GetDeviceQueue(indices.present, 0, &presentQueue);
		presentIndex = indices.present;
		foreach (bit; vkQueueFlagBits) {
			static if (bit == VkQueueFlagBits.VK_QUEUE_COMPUTE_BIT) {
				device.GetDeviceQueue(indices.compute, 0, &computeQueue);
				computeIndex = indices.compute;
			}
			else static if (bit == VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT) {
				device.GetDeviceQueue(indices.graphics, 0, &graphicsQueue);
				graphicsIndex = indices.graphics;
			}
			else static if (bit == VkQueueFlagBits.VK_QUEUE_SPARSE_BINDING_BIT) {
				device.GetDeviceQueue(indices.sparseBinding, 0, &sparseBindingQueue);
				sparseBindingIndex = indices.sparseBinding;
			}
			else static if (bit == VkQueueFlagBits.VK_QUEUE_TRANSFER_BIT) {
				device.GetDeviceQueue(indices.transfer, 0, &transferQueue);
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

		device.vkCreateSwapchainKHR(device.vkDevice, &createInfo, pAllocator,
				&swapChain).enforceVK("vkCreateSwapchainKHR");

		imageCount = 0;
		device.vkGetSwapchainImagesKHR(device.vkDevice, swapChain, &imageCount, null);
		swapChainImages.length = imageCount;
		device.vkGetSwapchainImagesKHR(device.vkDevice, swapChain, &imageCount, swapChainImages.ptr);

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

			device.CreateImageView(&createInfo, pAllocator,
					&swapChainImageViews[i]).enforceVK("vkCreateImageView #" ~ i.to!string);
		}
	}

	void createRenderPass() {
		VkAttachmentDescription colorAttachment;
		colorAttachment.format = swapChainImageFormat;
		colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT; // TODO: multisampling
		colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR; // TODO: change to DONT_CARE once we have a skybox
		colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
		colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
		colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

		VkAttachmentReference colorAttachmentRef;
		colorAttachmentRef.attachment = 0;
		colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

		VkSubpassDescription subpass;
		subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
		subpass.colorAttachmentCount = 1;
		subpass.pColorAttachments = &colorAttachmentRef;

		VkRenderPassCreateInfo renderPassInfo;
		renderPassInfo.attachmentCount = 1;
		renderPassInfo.pAttachments = &colorAttachment;
		renderPassInfo.subpassCount = 1;
		renderPassInfo.pSubpasses = &subpass;

		device.CreateRenderPass(&renderPassInfo, pAllocator, &renderPass)
			.enforceVK("vkCreateRenderPass");
	}

	void createGraphicsPipeline() {
		auto vertShaderModule = context.createShaderModule("shaders/vert.spv");
		scope (exit)
			device.DestroyShaderModule(vertShaderModule, pAllocator);

		auto fragShaderModule = context.createShaderModule("shaders/frag.spv");
		scope (exit)
			device.DestroyShaderModule(fragShaderModule, pAllocator);

		VkPipelineShaderStageCreateInfo vertShaderStageInfo;
		vertShaderStageInfo.stage = VK_SHADER_STAGE_VERTEX_BIT;
		vertShaderStageInfo._module = vertShaderModule;
		vertShaderStageInfo.pName = "main";

		// TODO: use pSpecializationInfo in shaders for constants (optimization like static if)

		VkPipelineShaderStageCreateInfo fragShaderStageInfo;
		fragShaderStageInfo.stage = VK_SHADER_STAGE_FRAGMENT_BIT;
		fragShaderStageInfo._module = fragShaderModule;
		fragShaderStageInfo.pName = "main";

		VkPipelineShaderStageCreateInfo[2] shaderStages = [vertShaderStageInfo, fragShaderStageInfo];

		VkPipelineVertexInputStateCreateInfo vertexInputInfo;
		VkPipelineInputAssemblyStateCreateInfo inputAssembly;
		inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

		VkViewport viewport;
		viewport.x = 0;
		viewport.y = 0;
		viewport.width = cast(float) swapChainExtent.width;
		viewport.height = cast(float) swapChainExtent.height;
		viewport.minDepth = 0;
		viewport.maxDepth = 1;

		VkRect2D scissor;
		scissor.offset = VkOffset2D(0, 0);
		scissor.extent = swapChainExtent;

		VkPipelineViewportStateCreateInfo viewportState;
		viewportState.viewportCount = 1;
		viewportState.pViewports = &viewport;
		viewportState.scissorCount = 1;
		viewportState.pScissors = &scissor;

		VkPipelineRasterizationStateCreateInfo rasterizer;
		rasterizer.depthClampEnable = VK_FALSE;
		rasterizer.rasterizerDiscardEnable = VK_FALSE;
		rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
		rasterizer.lineWidth = 1.0f;
		rasterizer.cullMode = VK_CULL_MODE_BACK_BIT;
		rasterizer.frontFace = VK_FRONT_FACE_CLOCKWISE;
		rasterizer.depthBiasEnable = VK_FALSE;
		rasterizer.depthBiasConstantFactor = 0.0f;
		rasterizer.depthBiasClamp = 0.0f;
		rasterizer.depthBiasSlopeFactor = 0.0f;

		VkPipelineMultisampleStateCreateInfo multisampling; // TODO: add anti aliasing
		multisampling.sampleShadingEnable = VK_FALSE;
		multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
		multisampling.minSampleShading = 1.0f;
		multisampling.pSampleMask = null;
		multisampling.alphaToCoverageEnable = VK_FALSE;
		multisampling.alphaToOneEnable = VK_FALSE;

		// TODO: VkPipelineDepthStencilStateCreateInfo for 3D

		VkPipelineColorBlendAttachmentState colorBlendAttachment;
		colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_A_BIT
			| VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT;
		colorBlendAttachment.blendEnable = VK_FALSE; // TODO: turn this on
		colorBlendAttachment.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
		colorBlendAttachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
		colorBlendAttachment.colorBlendOp = VK_BLEND_OP_ADD;
		colorBlendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
		colorBlendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
		colorBlendAttachment.alphaBlendOp = VK_BLEND_OP_ADD;

		VkPipelineColorBlendStateCreateInfo colorBlending;
		colorBlending.logicOpEnable = VK_FALSE;
		colorBlending.attachmentCount = 1;
		colorBlending.pAttachments = &colorBlendAttachment;

		// TODO: use VK_DYNAMIC_STATE_* here
		//VkDynamicState[2] dynamicStates = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_LINE_WIDTH];
		//VkPipelineDynamicStateCreateInfo dynamicState;
		//dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
		//dynamicState.dynamicStateCount = cast(uint) dynamicStates.length;
		//dynamicState.pDynamicStates = dynamicStates.ptr;

		VkPipelineLayoutCreateInfo pipelineLayoutInfo;
		pipelineLayoutInfo.setLayoutCount = 0;
		pipelineLayoutInfo.pSetLayouts = null;
		pipelineLayoutInfo.pushConstantRangeCount = 0;
		pipelineLayoutInfo.pPushConstantRanges = null;

		device.CreatePipelineLayout(&pipelineLayoutInfo, pAllocator,
				&pipelineLayout).enforceVK("vkCreatePipelineLayout");

		VkGraphicsPipelineCreateInfo pipelineInfo;
		pipelineInfo.stageCount = cast(uint) shaderStages.length;
		pipelineInfo.pStages = shaderStages.ptr;
		pipelineInfo.pVertexInputState = &vertexInputInfo;
		pipelineInfo.pInputAssemblyState = &inputAssembly;
		pipelineInfo.pViewportState = &viewportState;
		pipelineInfo.pRasterizationState = &rasterizer;
		pipelineInfo.pMultisampleState = &multisampling;
		pipelineInfo.pDepthStencilState = null;
		pipelineInfo.pColorBlendState = &colorBlending;
		pipelineInfo.pDynamicState = null;
		pipelineInfo.layout = pipelineLayout;
		pipelineInfo.renderPass = renderPass;
		pipelineInfo.subpass = 0;
		pipelineInfo.basePipelineHandle = null;
		pipelineInfo.basePipelineIndex = -1;

		device.CreateGraphicsPipelines(null, 1, &pipelineInfo, pAllocator,
				&graphicsPipeline).enforceVK("vkCreateGraphicsPipelines");
	}

	void createFramebuffers() {
		swapChainFramebuffers.length = swapChainImageViews.length;

		foreach (i, ref view; swapChainImageViews) {
			VkFramebufferCreateInfo framebufferInfo;
			framebufferInfo.renderPass = renderPass;
			framebufferInfo.attachmentCount = 1;
			framebufferInfo.pAttachments = &view;
			framebufferInfo.width = swapChainExtent.width;
			framebufferInfo.height = swapChainExtent.height;
			framebufferInfo.layers = 1;

			device.CreateFramebuffer(&framebufferInfo, pAllocator,
					&swapChainFramebuffers[i]).enforceVK("vkCreateFramebuffer #" ~ i.to!string);
		}
	}

	void createCommandPool() {
		VkCommandPoolCreateInfo poolInfo;
		poolInfo.queueFamilyIndex = graphicsIndex;
		poolInfo.flags = 0;
		device.CreateCommandPool(&poolInfo, pAllocator, &commandPool)
			.enforceVK("vkCreateCommandPool");
	}

	void createCommandBuffers() {
		commandBuffers.length = swapChainFramebuffers.length;

		VkCommandBufferAllocateInfo allocInfo;
		allocInfo.commandPool = commandPool;
		allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
		allocInfo.commandBufferCount = cast(uint) commandBuffers.length;

		device.AllocateCommandBuffers(&allocInfo, commandBuffers.ptr)
			.enforceVK("vkAllocateCommandBuffers");

		foreach (i, ref commandBuffer; commandBuffers) {
			VkCommandBufferBeginInfo beginInfo;
			beginInfo.flags = VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT;
			beginInfo.pInheritanceInfo = null;

			device.vkBeginCommandBuffer(commandBuffer, &beginInfo);

			VkRenderPassBeginInfo renderPassInfo;
			renderPassInfo.renderPass = renderPass;
			renderPassInfo.framebuffer = swapChainFramebuffers[i];
			renderPassInfo.renderArea.offset = VkOffset2D(0, 0);
			renderPassInfo.renderArea.extent = swapChainExtent;

			VkClearValue clearColor;
			clearColor.color.float32[0] = 0;
			clearColor.color.float32[1] = 0;
			clearColor.color.float32[2] = 0;
			clearColor.color.float32[3] = 1.0f;

			renderPassInfo.clearValueCount = 1;
			renderPassInfo.pClearValues = &clearColor;

			device.vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
			device.vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline);

			device.vkCmdDraw(commandBuffer, 3, 1, 0, 0);

			device.vkCmdEndRenderPass(commandBuffer);
			device.vkEndCommandBuffer(commandBuffer).enforceVK("vkEndCommandBuffer #" ~ i.to!string);
		}
	}
}
