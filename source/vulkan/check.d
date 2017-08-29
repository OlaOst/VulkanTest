module vulkan.check;

import std.conv : to;
import std.exception : enforce;

import erupted;


void checkVk(VkResult result)
{
  enforce(result == VK_SUCCESS, result.to!string);
}
