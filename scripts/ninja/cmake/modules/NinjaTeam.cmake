# NinjaTeam.cmake - Advanced utilities for Ninja team-based building
cmake_minimum_required(VERSION 3.16)

# Define Ninja team global properties
set(NINJA_TEAM_SIZE 12 CACHE STRING "Number of ninja team members")
set(NINJA_RECURSION_DEPTH 4 CACHE STRING "Recursion depth for ninja builds")
set(NINJA_PARALLEL_JOBS 8 CACHE STRING "Number of parallel jobs per ninja")
set(NINJA_MAX_MEMORY "4G" CACHE STRING "Maximum memory per ninja member")
set(NINJA_MAX_CPU 2 CACHE STRING "Maximum CPU cores per ninja member")
set(NINJA_LOG_LEVEL "INFO" CACHE STRING "Log level for ninja operations")
set(NINJA_BUILD_MODE "parallel" CACHE STRING "Build mode: parallel, recursive, adaptive")
set(NINJA_BENCHMARK_ENABLED ON CACHE BOOL "Enable performance benchmarking")
set(NINJA_MONITOR_ENABLED ON CACHE BOOL "Enable real-time monitoring")

# Initialize the ninja team
function(ninja_team_init)
    message(STATUS "Initializing Ninja team with ${NINJA_TEAM_SIZE} members")
    message(STATUS "  Recursion depth: ${NINJA_RECURSION_DEPTH}")
    message(STATUS "  Parallel jobs per ninja: ${NINJA_PARALLEL_JOBS}")
    message(STATUS "  Max memory per ninja: ${NINJA_MAX_MEMORY}")
    message(STATUS "  Max CPU per ninja: ${NINJA_MAX_CPU}")
    message(STATUS "  Build mode: ${NINJA_BUILD_MODE}")

    # Create build directories
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/team)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/logs)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/artifacts)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/benchmarks)

    # Create directories for each team member
    foreach(member_index RANGE 1 ${NINJA_TEAM_SIZE})
        file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/team/member-${member_index}/workspace)
        file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/team/member-${member_index}/logs)
        file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/team/member-${member_index}/cache)
        file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/team/member-${member_index}/benchmarks)

        # Create status file
        file(WRITE ${CMAKE_BINARY_DIR}/team/member-${member_index}/status.json
            "{\n  \"member_id\": ${member_index},\n  \"status\": \"initialized\",\n  \"tasks\": 0,\n  \"recursion_level\": 0,\n  \"performance_score\": 100\n}")
    endforeach()

    # Create team configuration file
    configure_file(
        ${CMAKE_CURRENT_LIST_DIR}/templates/team-config.json.in
        ${CMAKE_BINARY_DIR}/team/team-config.json
        @ONLY
    )

    message(STATUS "Ninja team initialized successfully")
endfunction()

# Create a task for the ninja team with workload distribution
function(ninja_team_task TASK_NAME WORKLOAD)
    message(STATUS "Creating task ${TASK_NAME} with workload ${WORKLOAD}")

    # Determine optimal distribution based on workload
    math(EXPR tasks_per_member "${WORKLOAD} / ${NINJA_TEAM_SIZE}")
    if(tasks_per_member LESS 1)
        set(tasks_per_member 1)
    endif()

    set(output_files)
    set(timestamp ${CMAKE_CURRENT_LIST_DIR}/timestamp.txt)
    file(WRITE ${timestamp} "${TASK_NAME}")

    # Create tasks for each team member
    foreach(member_index RANGE 1 ${NINJA_TEAM_SIZE})
        set(output_file "${CMAKE_BINARY_DIR}/team/member-${member_index}/${TASK_NAME}.done")
        list(APPEND output_files ${output_file})

        add_custom_command(
            OUTPUT ${output_file}
            COMMAND ${CMAKE_COMMAND} -E echo "Member ${member_index} executing ${TASK_NAME} with ${tasks_per_member} subtasks"
            COMMAND ${CMAKE_COMMAND} -E env
                NINJA_MEMBER_ID=${member_index}
                NINJA_TASK_NAME=${TASK_NAME}
                NINJA_SUBTASKS=${tasks_per_member}
                NINJA_MAX_MEMORY=${NINJA_MAX_MEMORY}
                NINJA_MAX_CPU=${NINJA_MAX_CPU}
                ${CMAKE_CURRENT_LIST_DIR}/tools/execute_task.sh
            COMMAND ${CMAKE_COMMAND} -E touch ${output_file}
            DEPENDS ${timestamp}
            COMMENT "Team member ${member_index} executing task: ${TASK_NAME}"
            VERBATIM
        )
    endforeach()

    add_custom_target(${TASK_NAME} ALL DEPENDS ${output_files})

    # Add benchmarking if enabled
    if(NINJA_BENCHMARK_ENABLED)
        add_custom_target(${TASK_NAME}_benchmark
            COMMAND ${CMAKE_COMMAND} -E echo "Benchmarking task ${TASK_NAME}"
            COMMAND ${CMAKE_CURRENT_LIST_DIR}/tools/benchmark_task.sh ${TASK_NAME}
            DEPENDS ${TASK_NAME}
            COMMENT "Benchmarking task: ${TASK_NAME}"
        )
    endif()

    # Create monitoring target if enabled
    if(NINJA_MONITOR_ENABLED)
        add_custom_target(${TASK_NAME}_monitor
            COMMAND ${CMAKE_CURRENT_LIST_DIR}/tools/monitor_task.sh ${TASK_NAME}
            COMMENT "Monitoring task: ${TASK_NAME}"
        )
    endif()
endfunction()

# Create a recursive team task with multiple recursion levels
function(ninja_team_recursive_task TASK_NAME MAX_RECURSION)
    message(STATUS "Creating recursive task ${TASK_NAME} with ${MAX_RECURSION} levels")

    set(output_files)
    set(timestamp ${CMAKE_CURRENT_LIST_DIR}/timestamp.txt)
    file(WRITE ${timestamp} "${TASK_NAME}_recursive")

    # Create tasks for each recursion level
    foreach(level RANGE 1 ${MAX_RECURSION})
        foreach(member_index RANGE 1 ${NINJA_TEAM_SIZE})
            set(output_file "${CMAKE_BINARY_DIR}/team/member-${member_index}/${TASK_NAME}_level${level}.done")
            list(APPEND output_files ${output_file})

            add_custom_command(
                OUTPUT ${output_file}
                COMMAND ${CMAKE_COMMAND} -E echo "Member ${member_index} executing ${TASK_NAME} at recursion level ${level}"
                COMMAND ${CMAKE_COMMAND} -E env
                    NINJA_MEMBER_ID=${member_index}
                    NINJA_TASK_NAME=${TASK_NAME}
                    NINJA_RECURSION_LEVEL=${level}
                    NINJA_MAX_RECURSION=${MAX_RECURSION}
                    NINJA_MAX_MEMORY=${NINJA_MAX_MEMORY}
                    NINJA_MAX_CPU=${NINJA_MAX_CPU}
                    NINJA_PARALLEL_JOBS=${NINJA_PARALLEL_JOBS}
                    ${CMAKE_CURRENT_LIST_DIR}/tools/execute_recursive_task.sh
                COMMAND ${CMAKE_COMMAND} -E touch ${output_file}
                DEPENDS ${timestamp}
                COMMENT "Team member ${member_index} executing recursive task: ${TASK_NAME} (level ${level})"
                VERBATIM
            )
        endforeach()
    endforeach()

    add_custom_target(${TASK_NAME}_recursive ALL DEPENDS ${output_files})

    # Add performance analysis for recursive tasks
    add_custom_target(${TASK_NAME}_recursive_analyze
        COMMAND ${CMAKE_CURRENT_LIST_DIR}/tools/analyze_recursive_performance.sh ${TASK_NAME} ${MAX_RECURSION}
        DEPENDS ${TASK_NAME}_recursive
        COMMENT "Analyzing performance of recursive task: ${TASK_NAME}"
    )
endfunction()

# Deploy with ninja team
function(ninja_team_deploy PROJECT_NAME VERSION)
    message(STATUS "Starting ninja team deployment for ${PROJECT_NAME} version ${VERSION}")

    # Create deployment tasks
    set(deployment_tasks
        "prepare_environment"
        "configure_network"
        "setup_database"
        "deploy_services"
        "verify_deployment"
        "setup_monitoring"
        "generate_reports"
    )

    # Call ninja team deployment script
    add_custom_target(${PROJECT_NAME}_deploy_all
        COMMAND ${CMAKE_COMMAND} -E env
            PROJECT_NAME=${PROJECT_NAME}
            PROJECT_VERSION=${VERSION}
            TEAM_SIZE=${NINJA_TEAM_SIZE}
            RECURSION_DEPTH=${NINJA_RECURSION_DEPTH}
            BUILD_MODE=${NINJA_BUILD_MODE}
            ${CMAKE_CURRENT_LIST_DIR}/../ninja-team-deploy.sh
        COMMENT "Deploying ${PROJECT_NAME} ${VERSION} with ninja team"
        VERBATIM
    )

    # Add individual deployment tasks
    foreach(task ${deployment_tasks})
        # Add recursive task for each deployment stage
        ninja_team_recursive_task("deploy_${task}" ${NINJA_RECURSION_DEPTH})

        # Make the main deployment target depend on all individual tasks
        add_dependencies(${PROJECT_NAME}_deploy_all "deploy_${task}_recursive")
    endforeach()

    # Add final report target
    add_custom_target(${PROJECT_NAME}_deployment_report
        COMMAND ${CMAKE_COMMAND} -E echo "Generating deployment report for ${PROJECT_NAME} ${VERSION}"
        COMMAND ${CMAKE_CURRENT_LIST_DIR}/tools/generate_deployment_report.sh ${PROJECT_NAME} ${VERSION}
        DEPENDS ${PROJECT_NAME}_deploy_all
        COMMENT "Generating final deployment report for ${PROJECT_NAME} ${VERSION}"
    )

    message(STATUS "Ninja team deployment setup completed")
endfunction()

# Setup ninja team adaptation based on system resources
function(ninja_team_adapt)
    # Detect system resources
    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
        execute_process(
            COMMAND nproc
            OUTPUT_VARIABLE available_cores
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        execute_process(
            COMMAND grep MemTotal /proc/meminfo
            COMMAND awk "{print int($2/1024/1024)}"
            OUTPUT_VARIABLE available_memory_gb
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
        execute_process(
            COMMAND powershell -command "(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors"
            OUTPUT_VARIABLE available_cores
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        execute_process(
            COMMAND powershell -command "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)"
            OUTPUT_VARIABLE available_memory_gb
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
        execute_process(
            COMMAND sysctl -n hw.ncpu
            OUTPUT_VARIABLE available_cores
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        execute_process(
            COMMAND sysctl -n hw.memsize
            COMMAND awk "{print int($1/1024/1024/1024)}"
            OUTPUT_VARIABLE available_memory_gb
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
    else()
        set(available_cores 4)
        set(available_memory_gb 8)
    endif()

    # Calculate optimal team size based on available resources
    math(EXPR optimal_team_size "${available_cores} / 2")
    if(optimal_team_size LESS 1)
        set(optimal_team_size 1)
    elseif(optimal_team_size GREATER ${NINJA_TEAM_SIZE})
        set(optimal_team_size ${NINJA_TEAM_SIZE})
    endif()

    # Calculate memory per ninja
    math(EXPR memory_per_ninja "${available_memory_gb} / ${optimal_team_size}")
    if(memory_per_ninja LESS 1)
        set(memory_per_ninja 1)
    endif()

    # Update team configuration
    set(NINJA_TEAM_SIZE ${optimal_team_size} CACHE STRING "Number of ninja team members" FORCE)
    set(NINJA_MAX_MEMORY "${memory_per_ninja}G" CACHE STRING "Maximum memory per ninja member" FORCE)
    set(NINJA_MAX_CPU "1" CACHE STRING "Maximum CPU cores per ninja member" FORCE)

    message(STATUS "Adapted ninja team configuration:")
    message(STATUS "  Team size: ${NINJA_TEAM_SIZE}")
    message(STATUS "  Memory per ninja: ${NINJA_MAX_MEMORY}")
    message(STATUS "  CPU per ninja: ${NINJA_MAX_CPU}")
endfunction()
