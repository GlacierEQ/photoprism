cmake_minimum_required(VERSION 3.10)

# Set the project name
project(MyProject)

# Add an executable
add_executable(MyExecutable main.cpp)

# Specify the C++ standard
set_property(TARGET MyExecutable PROPERTY CXX_STANDARD 11)
