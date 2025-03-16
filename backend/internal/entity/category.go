package entity

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jinzhu/gorm"
	"github.com/photoprism/photoprism2/backend/internal/event"
	"github.com/photoprism/photoprism2/backend/internal/logger"
)

// Category represents a hierarchical category in the system.
type Category struct {
	ID          uint       `gorm:"primary_key" json:"id"`
	UUID        uuid.UUID  `gorm:"type:uuid;not null;default:gen_random_uuid()" json:"uuid"`
	ParentID    *uint      `gorm:"index" json:"parentId"`
	Parent      *Category  `gorm:"foreignkey:ParentID" json:"-"`
	Children    []Category `gorm:"foreignkey:ParentID" json:"children,omitempty"`
	Name        string     `gorm:"type:varchar(255);not null" json:"name"`
	Slug        string     `gorm:"type:varchar(255);not null;unique_index" json:"slug"`
	Description string     `gorm:"type:text" json:"description"`
	Color       string     `gorm:"type:varchar(25)" json:"color"`
	Icon        string     `gorm:"type:varchar(50)" json:"icon"`
	OrderIndex  int        `gorm:"default:0" json:"orderIndex"`
	Photos      []Photo    `gorm:"many2many:photos_categories;" json:"photos,omitempty"`
	Metadata    []CategoryMetadata `gorm:"foreignkey:CategoryID" json:"metadata,omitempty"`
	CreatedAt   time.Time  `json:"createdAt"`
	UpdatedAt   time.Time  `json:"updatedAt"`
	DeletedAt   *time.Time `sql:"index" json:"deletedAt,omitempty"`
}

// CategoryMetadata represents custom metadata for a category.
type CategoryMetadata struct {
	CategoryID uint      `gorm:"primary_key" json:"categoryId"`
	Key        string    `gorm:"primary_key;type:varchar(255)" json:"key"`
	Value      string    `gorm:"type:text" json:"value"`
	CreatedAt  time.Time `json:"createdAt"`
	UpdatedAt  time.Time `json:"updatedAt"`
}

// TableName returns the database table name for the Category entity.
func (Category) TableName() string {
	return "categories"
}

// TableName returns the database table name for the CategoryMetadata entity.
func (CategoryMetadata) TableName() string {
	return "category_metadata"
}

// BeforeCreate ensures valid data before creating a record.
func (m *Category) BeforeCreate(tx *gorm.DB) error {
	if m.UUID == uuid.Nil {
		m.UUID = uuid.New()
	}
	if m.Slug == "" {
		m.Slug = Slug(m.Name)
	} else {
		m.Slug = Slug(m.Slug)
	}
	return nil
}

// BeforeUpdate ensures valid data before updating a record.
func (m *Category) BeforeUpdate(tx *gorm.DB) error {
	if m.Slug == "" {
		m.Slug = Slug(m.Name)
	} else {
		m.Slug = Slug(m.Slug)
	}
	return nil
}

// AfterCreate publishes an event after creation.
func (m *Category) AfterCreate(tx *gorm.DB) error {
	event.Publish("categories.created", event.Data{"category": m})
	return nil
}

// AfterUpdate publishes an event after update.
func (m *Category) AfterUpdate(tx *gorm.DB) error {
	event.Publish("categories.updated", event.Data{"category": m})
	return nil
}

// AfterDelete publishes an event after deletion.
func (m *Category) AfterDelete(tx *gorm.DB) error {
	event.Publish("categories.deleted", event.Data{"id": m.ID, "uuid": m.UUID})
	return nil
}

// CreateOrUpdate creates a new record or updates an existing one.
func (m *Category) CreateOrUpdate(db *gorm.DB) error {
	if m.ID == 0 {
		return db.Create(m).Error
	}
	return db.Save(m).Error
}

// FindCategoryByID returns a category by its ID.
func FindCategoryByID(db *gorm.DB, id uint) (*Category, error) {
	var category Category
	if err := db.First(&category, id).Error; err != nil {
		return nil, err
	}
	return &category, nil
}

// FindCategoryByUUID returns a category by its UUID.
func FindCategoryByUUID(db *gorm.DB, uuid uuid.UUID) (*Category, error) {
	var category Category
	if err := db.Where("uuid = ?", uuid).First(&category).Error; err != nil {
		return nil, err
	}
	return &category, nil
}

// FindCategoryBySlug returns a category by its slug.
func FindCategoryBySlug(db *gorm.DB, slug string) (*Category, error) {
	var category Category
	if err := db.Where("slug = ?", slug).First(&category).Error; err != nil {
		return nil, err
	}
	return &category, nil
}

// GetCategoryPath returns the full path of the category.
func GetCategoryPath(db *gorm.DB, id uint) (string, error) {
	var path []string
	currentID := id

	for {
		var category Category
		if err := db.First(&category, currentID).Error; err != nil {
			return "", err
		}

		path = append([]string{category.Slug}, path...)

		if category.ParentID == nil {
			break
		}

		currentID = *category.ParentID
	}

	return strings.Join(path, "/"), nil
}

// CreateCategoryFromPath creates categories from a path like "parent/child/grandchild"
func CreateCategoryFromPath(db *gorm.DB, path string, metadata map[string]string) (*Category, error) {
	parts := strings.Split(path, "/")
	if len(parts) == 0 {
		return nil, fmt.Errorf("invalid category path: %s", path)
	}

	var parentID *uint = nil
	var lastCategory *Category = nil

	for i, part := range parts {
		slug := Slug(part)
		var category Category

		err := db.Where("slug = ? AND parent_id IS NULL", slug).First(&category).Error
		if i > 0 {
			err = db.Where("slug = ? AND parent_id = ?", slug, parentID).First(&category).Error
		}

		if err != nil {
			if err == gorm.ErrRecordNotFound {
				// Create the category if it doesn't exist
				category = Category{
					ParentID: parentID,
					Name:     part,
					Slug:     slug,
				}

				if err := db.Create(&category).Error; err != nil {
					return nil, fmt.Errorf("failed to create category %s: %w", part, err)
				}
			} else {
				return nil, fmt.Errorf("error finding category %s: %w", part, err)
			}
		}

		parentID = &category.ID
		lastCategory = &category
	}

	// Add metadata if provided
	if lastCategory != nil && len(metadata) > 0 {
		for key, value := range metadata {
			meta := CategoryMetadata{
				CategoryID: lastCategory.ID,
				Key:        key,
				Value:      value,
			}
			if err := db.Create(&meta).Error; err != nil {
				logger.Warnf("failed to add metadata %s=%s to category: %s", key, value, err)
			}
		}
	}

	return lastCategory, nil
}
