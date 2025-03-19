package api

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jinzhu/gorm"
	"github.com/photoprism/photoprism2/backend/internal/entity"
	"github.com/photoprism/photoprism2/backend/internal/logger"
	"github.com/photoprism/photoprism2/backend/internal/service"
)

// CategoryAPI implements the categories API.
type CategoryAPI struct {
	categoryService *service.CategoryService
}

// NewCategoryAPI creates a new CategoryAPI.
func NewCategoryAPI(categoryService *service.CategoryService) *CategoryAPI {
	return &CategoryAPI{categoryService: categoryService}
}

// RegisterRoutes registers the category API routes.
func (api *CategoryAPI) RegisterRoutes(router *gin.RouterGroup) {
	categories := router.Group("/categories")
	{
		categories.GET("", api.GetCategories)
		categories.GET("/:id", api.GetCategory)
		categories.POST("", api.CreateCategory)
		categories.PUT("/:id", api.UpdateCategory)
		categories.DELETE("/:id", api.DeleteCategory)

		categories.POST("/path", api.CreateCategoryByPath)
		categories.GET("/tree", api.GetCategoryTree)
		categories.GET("/:id/photos", api.GetCategoryPhotos)
		categories.POST("/:id/photos/:photoId", api.AddPhotoToCategory)
		categories.DELETE("/:id/photos/:photoId", api.RemovePhotoFromCategory)
	}
}

// GetCategories returns all categories.
func (api *CategoryAPI) GetCategories(c *gin.Context) {
	var categories []entity.Category

	// Get parent ID filter if provided
	parentID := c.Query("parent")

	db := c.MustGet("db").(*gorm.DB)

	if parentID != "" {
		pid, err := strconv.ParseUint(parentID, 10, 32)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid parent ID"})
			return
		}

		pid32 := uint(pid)
		if err := db.Where("parent_id = ?", pid32).Find(&categories).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	} else {
		// Get all categories (flat)
		if err := db.Find(&categories).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	c.JSON(http.StatusOK, categories)
}

// GetCategoryTree returns the full hierarchical category tree.
func (api *CategoryAPI) GetCategoryTree(c *gin.Context) {
	categories, err := api.categoryService.GetCategoryTree()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, categories)
}

// GetCategory returns a specific category.
func (api *CategoryAPI) GetCategory(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid category ID"})
		return
	}

	category, err := api.categoryService.GetCategory(uint(id))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "category not found"})
		return
	}

	c.JSON(http.StatusOK, category)
}

// CreateCategory creates a new category.
func (api *CategoryAPI) CreateCategory(c *gin.Context) {
	var category entity.Category
	if err := c.ShouldBindJSON(&category); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := api.categoryService.CreateCategory(&category); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, category)
}

// CreateCategoryByPath creates or gets a category from a path string.
func (api *CategoryAPI) CreateCategoryByPath(c *gin.Context) {
	type PathRequest struct {
		Path     string            `json:"path" binding:"required"`
		Metadata map[string]string `json:"metadata"`
	}

	var req PathRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	category, err := api.categoryService.CreateCategoryWithPath(req.Path, req.Metadata)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, category)
}

// UpdateCategory updates a category.
func (api *CategoryAPI) UpdateCategory(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid category ID"})
		return
	}

	var category entity.Category
	if err := c.ShouldBindJSON(&category); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	category.ID = uint(id)
	if err := api.categoryService.UpdateCategory(&category); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, category)
}

// DeleteCategory deletes a category.
func (api *CategoryAPI) DeleteCategory(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid category ID"})
		return
	}

	if err := api.categoryService.DeleteCategory(uint(id)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}

// GetCategoryPhotos returns all photos in a category.
func (api *CategoryAPI) GetCategoryPhotos(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid category ID"})
		return
	}

	photos, err := api.categoryService.GetCategoryPhotos(uint(id))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, photos)
}

// AddPhotoToCategory adds a photo to a category.
func (api *CategoryAPI) AddPhotoToCategory(c *gin.Context) {
	categoryID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid category ID"})
		return
	}

	photoID, err := strconv.ParseUint(c.Param("photoId"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid photo ID"})
		return
	}

	if err := api.categoryService.AddPhotoToCategory(uint(photoID), uint(categoryID)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}

// RemovePhotoFromCategory removes a photo from a category.
func (api *CategoryAPI) RemovePhotoFromCategory(c *gin.Context) {
	categoryID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid category ID"})
		return
	}

	photoID, err := strconv.ParseUint(c.Param("photoId"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid photo ID"})
		return
	}

	if err := api.categoryService.RemovePhotoFromCategory(uint(photoID), uint(categoryID)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}
