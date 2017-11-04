import std.stdio;
import std.math;
import std.string;

import erupted;

import glfw3d;

import game.vulkan.wrap;
import game.vulkan.window;

void main() {
	DerelictErupted.load();

	glfw3dInit();
	scope (exit)
		glfw3dTerminate();

	VulkanWindow w = new VulkanWindow(853, 600, "WhyLinux");

	{
		ApplicationInfo appInfo;
		appInfo.applicationName = "WhyLinux";
		appInfo.applicationVersion = VulkanVersion(1, 0, 0);
		appInfo.engineName = "WhyLinuxEngine";
		appInfo.engineVersion = VulkanVersion(0, 1, 0);
		appInfo.apiVersion = VulkanVersion.api1_0;

		VkInstanceCreateInfo createInfo;
		createInfo.pApplicationInfo = &appInfo.info;

		createInfo.fillRequiredInstanceExtensions();

		createInfo.enabledLayerCount = 0;

		w.createInstance(&createInfo);
	}

	while (!w.shouldClose()) {
		glfwPollEvents();
	}
}
