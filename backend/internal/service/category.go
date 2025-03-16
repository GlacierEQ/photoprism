package service

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"

	"github.com/jinzhu/gorm"
	"github.com/photoprism/photoprism2/backend/internal/entity"
	"github.com/photoprism/photoprism2/backend/internal/logger"
	"gopkg.in/yaml.v2"
)

// CategoryService provides methods for managing categories.
type CategoryService struct {
	db *gorm.DB
}

// NewCategoryService creates a new CategoryService.
func NewCategoryService(db *gorm.DB) *CategoryService {
	return &CategoryService{db: db}
}

// CategoryTree represents a hierarchical structure of categories.
type CategoryTree struct {
	Version    string         `json:"version" yaml:"version"`
	Categories []CategoryNode `json:"categories" yaml:"categories"`
}

// CategoryNode represents a node in the category tree.
type CategoryNode struct {
	Name        string         `json:"name" yaml:"name"`
	Slug        string         `json:"slug" yaml:"slug"`
	Icon        string         `json:"icon" yaml:"icon"`
	Color       string         `json:"color" yaml:"color"`
	Description string         `json:"description" yaml:"description"`
	OrderIndex  int            `json:"orderIndex" yaml:"orderIndex"`
	Metadata    map[string]string `json:"metadata" yaml:"metadata"`
	Children    []CategoryNode `json:"children" yaml:"children"`
}

// GetCategory retrieves a category by ID.
func (s *CategoryService) GetCategory(id uint) (*entity.Category, error) {
	return entity.FindCategoryByID(s.db, id)
}

// CreateCategory creates a new category.
func (s *CategoryService) CreateCategory(category *entity.Category) error {
	return category.CreateOrUpdate(s.db)
}

// UpdateCategory updates an existing category.
func (s *CategoryService) UpdateCategory(category *entity.Category) error {
	return category.CreateOrUpdate(s.db)
}

// DeleteCategory deletes a category by ID.
func (s *CategoryService) DeleteCategory(id uint) error {
	return s.db.Delete(&entity.Category{}, id).Error
}

// GetCategoryPath returns the full path of a category.
func (s *CategoryService) GetCategoryPath(id uint) (string, error) {
	return entity.GetCategoryPath(s.db, id)
}

// GetCategoryByPath finds or creates categories from a path.
func (s *CategoryService) GetCategoryByPath(path string) (*entity.Category, error) {
	return entity.CreateCategoryFromPath(s.db, path, nil)
}

// CreateCategoryWithPath creates a category with its full hierarchical path.
func (s *CategoryService) CreateCategoryWithPath(path string, metadata map[string]string) (*entity.Category, error) {
	return entity.CreateCategoryFromPath(s.db, path, metadata)
}

// AddPhotoToCategory adds a photo to a category.
func (s *CategoryService) AddPhotoToCategory(photoID, categoryID uint) error {
	return s.db.Exec("INSERT INTO photos_categories (photo_id, category_id) VALUES (?, ?) ON CONFLICT DO NOTHING", photoID, categoryID).Error
}

// RemovePhotoFromCategory removes a photo from a category.
func (s *CategoryService) RemovePhotoFromCategory(photoID, categoryID uint) error {
	return s.db.Exec("DELETE FROM photos_categories WHERE photo_id = ? AND category_id = ?", photoID, categoryID).Error
}

// GetCategoryPhotos retrieves all photos in a category.
func (s *CategoryService) GetCategoryPhotos(categoryID uint) ([]entity.Photo, error) {
	var photos []entity.Photo
	err := s.db.Joins("JOIN photos_categories ON photos_categories.photo_id = photos.id").
		Where("photos_categories.category_id = ?", categoryID).
		Find(&photos).Error
	return photos, err
}

// GetCategoryTree retrieves the entire category tree.
func (s *CategoryService) GetCategoryTree() ([]entity.Category, error) {
	var categories []entity.Category
	err := s.db.Where("parent_id IS NULL").Order("order_index ASC, name ASC").Find(&categories).Error
	if err != nil {
		return nil, err
	}

	// Load children recursively
	for i := range categories {
		if err := s.loadChildren(&categories[i]); err != nil {
			return nil, err
		}
	}

	return categories, nil
}

// loadChildren recursively loads all children of a category.
func (s *CategoryService) loadChildren(category *entity.Category) error {
	if category == nil {
		return nil
	}

	var children []entity.Category
	if err := s.db.Where("parent_id = ?", category.ID).Order("order_index ASC, name ASC").Find(&children).Error; err != nil {
		return err
	}

	category.Children = children

	for i := range children {
		if err := s.loadChildren(&children[i]); err != nil {
			return err
		}
	}

	return nil
}

// ImportFromFile imports a category tree from a YAML or JSON file.
func (s *CategoryService) ImportFromFile(filePath string) error {
	data, err := ioutil.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to read file: %w", err)
	}

	var tree CategoryTree

	// Determine file type by extension
	switch filepath.Ext(filePath) {
	case ".yml", ".yaml":
		if err := yaml.Unmarshal(data, &tree); err != nil {
			return fmt.Errorf("failed to parse YAML: %w", err)
		}
	case ".json":
		if err := json.Unmarshal(data, &tree); err != nil {
			return fmt.Errorf("failed to parse JSON: %w", err)
		}
	default:
		return fmt.Errorf("unsupported file format: %s", filepath.Ext(filePath))
	}

	return s.importCategoryTree(tree)
}

// importCategoryTree imports the category tree into the database.
func (s *CategoryService) importCategoryTree(tree CategoryTree) error {
	logger.Infof("importing category tree version %s with %d top-level categories",
		tree.Version, len(tree.Categories))

	// Import top-level categories
	for _, node := range tree.Categories {
		if err := s.createCategoryFromNode(nil, &node); err != nil {
			return err
		}
	}

	return nil
}

// createCategoryFromNode recursively creates categories from a node structure.
func (s *CategoryService) createCategoryFromNode(parentID *uint, node *CategoryNode) error {
	// Create the category
	category := entity.Category{
		ParentID:    parentID,
		Name:        node.Name,
		Slug:        node.Slug,
		Description: node.Description,
		Color:       node.Color,
		Icon:        node.Icon,
		OrderIndex:  node.OrderIndex,
	}

	if err := s.db.Create(&category).Error; err != nil {
		return fmt.Errorf("failed to create category %s: %w", node.Name, err)
	}

	// Add metadata if any
	if len(node.Metadata) > 0 {
		for key, value := range node.Metadata {
			meta := entity.CategoryMetadata{
				CategoryID: category.ID,
				Key:        key,
				Value:      value,
			}
			if err := s.db.Create(&meta).Error; err != nil {
				logger.Warnf("failed to add metadata %s=%s to category %s: %s",
					key, value, node.Name, err)
			}
		}
	}

	// Process children recursively
	for _, child := range node.Children {
		if err := s.createCategoryFromNode(&category.ID, &child); err != nil {
			return err
		}
	}

	return nil
}

// ImportDefaultCategories imports categories from the default configuration file.
func (s *CategoryService) ImportDefaultCategories(configPath string) error {
	defaultFile := filepath.Join(configPath, "default-categories.yml")
	if _, err := os.Stat(defaultFile); os.IsNotExist(err) {
		logger.Infof("no default categories file found at %s", defaultFile)
		return nil
	}

	logger.Infof("importing default categories from %s", defaultFile)
	return s.ImportFromFile(defaultFile)
}
