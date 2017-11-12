module game.vulkan.window;

import erupted;

import glfw3d;
import gl3n.linalg;
import gl3n.math;

import game.vulkan.context;
import game.vulkan.disposer;
import game.vulkan.mesh;
import game.vulkan.shader;
import game.vulkan.wrap;

import std.conv;
import std.datetime.stopwatch;
import std.file : readFile = read;
import std.traits;

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

	ref auto device() {
		return context.device;
	}

	ref auto disposer() {
		return context.disposer;
	}

	this(int width, int height, string name) {
		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);
		super(width, height, name);

		context.disposer = Disposer(context);
		context.swapChainDisposer = Disposer(context);
	}

	override void destroy() {
		device.DeviceWaitIdle();
		destroySwapChain();
		disposer.dispose();
		super.destroy();
	}

	void destroySwapChain() {
		swapChainDisposer.dispose();
	}

	void createSurface() {
		glfwCreateWindowSurface(instance, ptr, pAllocator, &surface).enforceVK(
				"glfwCreateWindowSurface");
		disposer.register({
			vkDestroySurfaceKHR(context.instance, context.surface, context.pAllocator);
		});
	}

	void createInstance(const(VkInstanceCreateInfo)* pCreateInfo)
	in {
		assert(pCreateInfo);
	}
	body {
		vkCreateInstance(pCreateInfo, pAllocator, &instance).enforceVK("vkCreateInstance");
		loadInstanceLevelFunctions(instance);
		disposer.register({ vkDestroyInstance(context.instance, context.pAllocator); });
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

		vkGetPhysicalDeviceFeatures(physicalDevice, &deviceFeatures);

		VkDevice vkdev;
		vkCreateDevice(physicalDevice, &createInfoBase, pAllocator, &vkdev).enforceVK("vkCreateDevice");

		device.loadDeviceLevelFunctions(vkdev);
		disposer.register({ context.device.DestroyDevice(context.pAllocator); });

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

	void recreateSwapChain() {
		device.DeviceWaitIdle();

		destroySwapChain();

		createSwapChain();
		createImageViews();
		createRenderPass();
		createGraphicsPipeline();
		createDepthResources();
		createFramebuffers();
		createCommandBuffers();
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
		createInfo.oldSwapchain = VK_NULL_ND_HANDLE; // TODO: for recreation of swapchain

		device.vkCreateSwapchainKHR(device.vkDevice, &createInfo, pAllocator,
				&swapChain).enforceVK("vkCreateSwapchainKHR");

		swapChainDisposer.register({
			context.device.vkDestroySwapchainKHR(context.device.vkDevice,
				context.swapChain, context.pAllocator);
		});

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
			swapChainImageViews[i] = context.createImageView(image, swapChainImageFormat);
		}

		swapChainDisposer.register!"DestroyImageView"(swapChainImageViews);
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

		VkAttachmentDescription depthAttachment;
		depthAttachment.format = context.findDepthFormat;
		depthAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
		depthAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
		depthAttachment.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		depthAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		depthAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		depthAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
		depthAttachment.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

		VkAttachmentReference depthAttachmentRef;
		depthAttachmentRef.attachment = 1;
		depthAttachmentRef.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

		VkSubpassDescription subpass;
		subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
		subpass.colorAttachmentCount = 1;
		subpass.pColorAttachments = &colorAttachmentRef;
		subpass.pDepthStencilAttachment = &depthAttachmentRef;

		VkAttachmentDescription[2] attachments = [colorAttachment, depthAttachment];

		VkSubpassDependency subpassDependency;
		subpassDependency.srcSubpass = VK_SUBPASS_EXTERNAL;
		subpassDependency.dstSubpass = 0;
		subpassDependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
		subpassDependency.srcAccessMask = 0;
		subpassDependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
		subpassDependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_READ_BIT
			| VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

		VkRenderPassCreateInfo renderPassInfo;
		renderPassInfo.attachmentCount = cast(uint) attachments.length;
		renderPassInfo.pAttachments = attachments.ptr;
		renderPassInfo.subpassCount = 1;
		renderPassInfo.pSubpasses = &subpass;
		renderPassInfo.dependencyCount = 1;
		renderPassInfo.pDependencies = &subpassDependency;

		device.CreateRenderPass(&renderPassInfo, pAllocator, &renderPass)
			.enforceVK("vkCreateRenderPass");
		swapChainDisposer.register!"DestroyRenderPass"(renderPass);
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

		auto bindingDescription = PositionNormalTexCoordVertex.bindingDescription;
		auto attributeDescriptions = PositionNormalTexCoordVertex.attributeDescriptions;

		VkPipelineVertexInputStateCreateInfo vertexInputInfo;
		vertexInputInfo.vertexBindingDescriptionCount = 1;
		vertexInputInfo.vertexAttributeDescriptionCount = cast(uint) attributeDescriptions.length;
		vertexInputInfo.pVertexBindingDescriptions = &bindingDescription;
		vertexInputInfo.pVertexAttributeDescriptions = attributeDescriptions.ptr;

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
		rasterizer.cullMode = VK_CULL_MODE_NONE;
		rasterizer.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
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

		VkPipelineDepthStencilStateCreateInfo depthStencil;
		depthStencil.depthTestEnable = VK_TRUE;
		depthStencil.depthWriteEnable = VK_TRUE;
		depthStencil.depthCompareOp = VK_COMPARE_OP_LESS;
		depthStencil.depthBoundsTestEnable = VK_FALSE;
		depthStencil.minDepthBounds = 0.0f;
		depthStencil.maxDepthBounds = 0.0f;
		depthStencil.stencilTestEnable = VK_FALSE;

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
		pipelineLayoutInfo.setLayoutCount = 1;
		pipelineLayoutInfo.pSetLayouts = &descriptorSetLayout;
		pipelineLayoutInfo.pushConstantRangeCount = 0;
		pipelineLayoutInfo.pPushConstantRanges = null;

		device.CreatePipelineLayout(&pipelineLayoutInfo, pAllocator,
				&pipelineLayout).enforceVK("vkCreatePipelineLayout");
		swapChainDisposer.register!"DestroyPipelineLayout"(pipelineLayout);

		VkGraphicsPipelineCreateInfo pipelineInfo;
		pipelineInfo.stageCount = cast(uint) shaderStages.length;
		pipelineInfo.pStages = shaderStages.ptr;
		pipelineInfo.pVertexInputState = &vertexInputInfo;
		pipelineInfo.pInputAssemblyState = &inputAssembly;
		pipelineInfo.pViewportState = &viewportState;
		pipelineInfo.pRasterizationState = &rasterizer;
		pipelineInfo.pMultisampleState = &multisampling;
		pipelineInfo.pDepthStencilState = &depthStencil;
		pipelineInfo.pColorBlendState = &colorBlending;
		pipelineInfo.pDynamicState = null;
		pipelineInfo.layout = pipelineLayout;
		pipelineInfo.renderPass = renderPass;
		pipelineInfo.subpass = 0;
		pipelineInfo.basePipelineHandle = VK_NULL_ND_HANDLE;
		pipelineInfo.basePipelineIndex = -1;

		device.CreateGraphicsPipelines(VK_NULL_ND_HANDLE, 1, &pipelineInfo,
				pAllocator, &graphicsPipeline).enforceVK("vkCreateGraphicsPipelines");
		swapChainDisposer.register!"DestroyPipeline"(graphicsPipeline);
	}

	void createFramebuffers() {
		swapChainFramebuffers.length = swapChainImageViews.length;

		foreach (i, ref view; swapChainImageViews) {
			VkImageView[2] attachments = [view, depthImageView];

			VkFramebufferCreateInfo framebufferInfo;
			framebufferInfo.renderPass = renderPass;
			framebufferInfo.attachmentCount = cast(uint) attachments.length;
			framebufferInfo.pAttachments = attachments.ptr;
			framebufferInfo.width = swapChainExtent.width;
			framebufferInfo.height = swapChainExtent.height;
			framebufferInfo.layers = 1;

			device.CreateFramebuffer(&framebufferInfo, pAllocator,
					&swapChainFramebuffers[i]).enforceVK("vkCreateFramebuffer #" ~ i.to!string);
		}
		swapChainDisposer.register!"DestroyFramebuffer"(swapChainFramebuffers);
	}

	void createDescriptorPool() {
		VkDescriptorPoolSize[2] poolSizes;
		poolSizes[0].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		poolSizes[0].descriptorCount = 1;
		poolSizes[1].type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
		poolSizes[1].descriptorCount = 1;

		VkDescriptorPoolCreateInfo poolInfo;
		poolInfo.poolSizeCount = cast(uint) poolSizes.length;
		poolInfo.pPoolSizes = poolSizes.ptr;
		poolInfo.maxSets = 1;

		device.CreateDescriptorPool(&poolInfo, pAllocator, &descriptorPool)
			.enforceVK("vkCreateDescriptorPool");
		disposer.register!"DestroyDescriptorPool"(descriptorPool);
	}

	void createCommandPool() {
		VkCommandPoolCreateInfo poolInfo;
		poolInfo.queueFamilyIndex = graphicsIndex;
		poolInfo.flags = 0;
		device.CreateCommandPool(&poolInfo, pAllocator, &commandPool)
			.enforceVK("vkCreateCommandPool");
		disposer.register!"DestroyCommandPool"(commandPool);
	}

	void createDepthResources() {
		VkFormat depthFormat = context.findDepthFormat;
		context.createImage(swapChainExtent.width, swapChainExtent.height, depthFormat, VK_IMAGE_TILING_OPTIMAL,
				VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
				VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, depthImage, depthImageMemory);
		depthImageView = context.createImageView(depthImage, depthFormat, VK_IMAGE_ASPECT_DEPTH_BIT);
		context.transitionImageLayout(depthImage, depthFormat,
				VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);

		swapChainDisposer.register!"DestroyImageView"(depthImageView);
		swapChainDisposer.register(depthImage, depthImageMemory);
	}

	void createCommandBuffers() {
		commandBuffers.length = swapChainFramebuffers.length;

		VkCommandBufferAllocateInfo allocInfo;
		allocInfo.commandPool = commandPool;
		allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
		allocInfo.commandBufferCount = cast(uint) commandBuffers.length;

		device.AllocateCommandBuffers(&allocInfo, commandBuffers.ptr)
			.enforceVK("vkAllocateCommandBuffers");
		swapChainDisposer.register({
			context.device.FreeCommandBuffers(context.commandPool,
				cast(uint) context.commandBuffers.length, context.commandBuffers.ptr);
		});

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

			VkClearValue[2] clearValues;
			clearValues[0].color.float32[0] = 0;
			clearValues[0].color.float32[1] = 0;
			clearValues[0].color.float32[2] = 0;
			clearValues[0].color.float32[3] = 1.0f;
			clearValues[1].depthStencil = VkClearDepthStencilValue(1.0f, 0);

			renderPassInfo.clearValueCount = cast(uint) clearValues.length;
			renderPassInfo.pClearValues = clearValues.ptr;

			device.vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
			device.vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline);

			onBuildRenderpass(commandBuffer);

			device.vkCmdEndRenderPass(commandBuffer);
			device.vkEndCommandBuffer(commandBuffer).enforceVK("vkEndCommandBuffer #" ~ i.to!string);
		}
	}

	void createSemaphores() {
		VkSemaphoreCreateInfo semaphoreInfo;
		device.CreateSemaphore(&semaphoreInfo, pAllocator, &imageAvailableSemaphore)
			.enforceVK("vkCreateSemaphore imageAvailableSemaphore");
		device.CreateSemaphore(&semaphoreInfo, pAllocator, &renderFinishedSemaphore)
			.enforceVK("vkCreateSemaphore renderFinishedSemaphore");
		disposer.register!"DestroySemaphore"(renderFinishedSemaphore);
		disposer.register!"DestroySemaphore"(imageAvailableSemaphore);
	}

	final int width() {
		return swapChainExtent.width;
	}

	final int height() {
		return swapChainExtent.height;
	}

	StopWatch updateTimer;
	double time = 0;
	double fracTime = 0;
	int frames;

	void update() {
		updateTimer.stop();
		double delta = updateTimer.peek.total!"hnsecs" / 10_000_000.0;
		updateTimer.reset();
		updateTimer.start();

		if (delta < 0)
			delta = 0.001;
		else if (delta > 1)
			delta = 1;

		time += delta;
		fracTime += delta;

		frames++;

		if (fracTime > 1) {
			import std.stdio;

			writeln(frames, " fps");
			frames = 0;
			fracTime -= 1;
		}

		onUpdate(delta);

		// TODO: look at push constants
	}

	void drawFrame() {
		update();

		device.vkQueueWaitIdle(presentQueue);

		uint imageIndex;
		auto result = device.vkAcquireNextImageKHR(device.vkDevice, swapChain,
				ulong.max, imageAvailableSemaphore, VK_NULL_ND_HANDLE, &imageIndex);

		if (result == VK_ERROR_OUT_OF_DATE_KHR)
			return recreateSwapChain();
		else if (result != VK_SUBOPTIMAL_KHR && result != VK_SUCCESS)
			enforceVK(result, "vkAcquireNextImageKHR");

		VkSemaphore[1] waitSemaphores = [imageAvailableSemaphore];
		VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

		VkSubmitInfo submitInfo;
		submitInfo.waitSemaphoreCount = cast(uint) waitSemaphores.length;
		submitInfo.pWaitSemaphores = waitSemaphores.ptr;
		submitInfo.pWaitDstStageMask = &waitStage;
		submitInfo.commandBufferCount = 1;
		submitInfo.pCommandBuffers = &commandBuffers[imageIndex];

		VkSemaphore[1] signalSemaphores = [renderFinishedSemaphore];
		submitInfo.signalSemaphoreCount = cast(uint) signalSemaphores.length;
		submitInfo.pSignalSemaphores = &renderFinishedSemaphore;

		device.vkQueueSubmit(graphicsQueue, 1, &submitInfo, VK_NULL_ND_HANDLE)
			.enforceVK("vkQueueSubmit");

		VkPresentInfoKHR presentInfo;
		presentInfo.waitSemaphoreCount = cast(uint) signalSemaphores.length;
		presentInfo.pWaitSemaphores = signalSemaphores.ptr;

		presentInfo.swapchainCount = 1;
		presentInfo.pSwapchains = &swapChain;
		presentInfo.pImageIndices = &imageIndex;

		presentInfo.pResults = null;

		result = device.vkQueuePresentKHR(presentQueue, &presentInfo);

		if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR)
			recreateSwapChain();
		else if (result != VK_SUCCESS)
			enforceVK(result, "vkQueuePresentKHR");

		device.vkQueueWaitIdle(presentQueue);
	}

	abstract void createDescriptorSet();
	abstract void onLoad();
	abstract void onUpdate(double delta);
	abstract void onBuildRenderpass(VkCommandBuffer commandBuffer);
}
