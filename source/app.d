import std.stdio;
import std.math;
import std.string;

import glfw3d;

import game.vulkan.window;

void main() {
	glfw3dInit();
	scope (exit)
		glfw3dTerminate();

	VulkanWindow w = new VulkanWindow(853, 600, "WhyLinux");

	while (!w.shouldClose()) {
		glfwPollEvents();
	}
}
