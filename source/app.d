import std.stdio;
import std.math;
import std.string;

import glfw3d;

void main() {
	glfw3dInit();
	scope (exit)
		glfw3dTerminate();

	Window w = new Window(853, 600, "WhyLinux");

	while (!w.shouldClose()) {
		glfwPollEvents();

		w.swapBuffers();
	}
}
