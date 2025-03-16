package setup

import (
	"github.com/jinzhu/gorm"
	"github.com/photoprism/photoprism2/backend/internal/config"
	"github.com/photoprism/photoprism2/backend/internal/logger"
	"github.com/photoprism/photoprism2/backend/internal/service"
)

// Categories initializes the category system.
func Categories(conf *config.Config, db *gorm.DB) error {
	logger.Info("initializing category system")

	categoryService := service.NewCategoryService(db)

	// Check if categories exist
	var count int
	if err := db.Model(&entity.Category{}).Count(&count).Error; err != nil {
		return err
	}

	// Only import default categories if there are none
	if count == 0 {
		logger.Info("no categories found, importing defaults")
		if err := categoryService.ImportDefaultCategories(conf.ConfigPath()); err != nil {
			logger.Warnf("failed to import default categories: %s", err)
			// Continue even if import fails
		}
	} else {
		logger.Infof("found %d existing categories, skipping import", count)
	}

	return nil
}
