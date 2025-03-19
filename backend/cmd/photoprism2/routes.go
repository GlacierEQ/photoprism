package main

import (
	"github.com/gin-gonic/gin"
	"github.com/photoprism/photoprism2/backend/internal/api"
	"github.com/photoprism/photoprism2/backend/internal/service"
)

// setupRoutes configures the API routes
func setupRoutes(r *gin.Engine, services *service.Services) {
	// API v1 routes group
	v1 := r.Group("/api/v1")

	// Health check endpoint
	v1.GET("/health", api.HealthCheck)

	// Photo API
	photoAPI := api.NewPhotoAPI(services.PhotoService)
	photoAPI.RegisterRoutes(v1)

	// Album API
	albumAPI := api.NewAlbumAPI(services.AlbumService)
	albumAPI.RegisterRoutes(v1)

	// Category API (new)
	categoryAPI := api.NewCategoryAPI(services.CategoryService)
	categoryAPI.RegisterRoutes(v1)

	// User API
	userAPI := api.NewUserAPI(services.UserService)
	userAPI.RegisterRoutes(v1)

	// Auth API
	authAPI := api.NewAuthAPI(services.AuthService)
	authAPI.RegisterRoutes(v1)

	// Settings API
	settingsAPI := api.NewSettingsAPI(services.SettingsService)
	settingsAPI.RegisterRoutes(v1)

	// Additional APIs can be registered here

	// Static files for frontend
	r.Static("/assets", "./frontend/dist/assets")
	r.StaticFile("/", "./frontend/dist/index.html")
	r.StaticFile("/favicon.ico", "./frontend/dist/favicon.ico")
}
