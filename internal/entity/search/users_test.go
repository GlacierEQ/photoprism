package search

import (
	"testing"

	"github.com/photoprism/photoprism/internal/entity/sortby"

	"github.com/stretchr/testify/assert"

	"github.com/photoprism/photoprism/internal/form"
)

func TestUsers(t *testing.T) {
	t.Run("Default", func(t *testing.T) {
		if results, err := Users(form.SearchUsers{}); err != nil {
			t.Fatal(err)
		} else {
			assert.LessOrEqual(t, 2, len(results))
			//t.Logf("sessions: %#v", results)
		}
	})
	t.Run("Limit", func(t *testing.T) {
		if results, err := Users(form.SearchUsers{Count: 1}); err != nil {
			t.Fatal(err)
		} else {
			assert.LessOrEqual(t, 1, len(results))
			//t.Logf("sessions: %#v", results)
		}
	})
	t.Run("Offset", func(t *testing.T) {
		if results, err := Users(form.SearchUsers{Offset: 1}); err != nil {
			t.Fatal(err)
		} else {
			assert.LessOrEqual(t, 2, len(results))
			//t.Logf("sessions: %#v", results)
		}
	})
	t.Run("SearchAlice", func(t *testing.T) {
		if results, err := Users(form.SearchUsers{Count: 100, Query: "alice"}); err != nil {
			t.Fatal(err)
		} else {
			// t.Logf("users: %#v", results)
			assert.LessOrEqual(t, 1, len(results))
			if len(results) > 0 {
				assert.Equal(t, 5, results[0].ID)
				assert.Equal(t, "uqxetse3cy5eo9z2", results[0].UserUID)
				assert.Equal(t, "alice", results[0].UserName)
			}
		}
	})
	t.Run("SortByName", func(t *testing.T) {
		if results, err := Users(form.SearchUsers{Count: 100, Order: sortby.Name}); err != nil {
			t.Fatal(err)
		} else {
			// t.Logf("users: %#v", results)
			assert.LessOrEqual(t, 1, len(results))
			if len(results) > 0 {
				assert.Equal(t, "2fa", results[0].UserName)
				assert.Equal(t, "admin", results[1].UserName)
			}
		}
	})
	t.Run("SortByDisplayName", func(t *testing.T) {
		if results, err := Users(form.SearchUsers{Count: 100, Order: sortby.DisplayName}); err != nil {
			t.Fatal(err)
		} else {
			// t.Logf("users: %#v", results)
			assert.LessOrEqual(t, 1, len(results))
			if len(results) > 0 {
				assert.Equal(t, "2FA Enabled", results[0].DisplayName)
				assert.Equal(t, "Admin", results[1].DisplayName)
			}
		}
	})
	t.Run("SortByEmail", func(t *testing.T) {
		if results, err := Users(form.SearchUsers{Count: 100, Offset: 1, Order: sortby.Email}); err != nil {
			t.Fatal(err)
		} else {
			// t.Logf("users: %#v", results)
			assert.LessOrEqual(t, 1, len(results))
			if len(results) > 0 {
				assert.Equal(t, "2FA@example.com", results[0].UserEmail)
				assert.Equal(t, "alice@example.com", results[1].UserEmail)
			}
		}
	})
	t.Run("SearchId", func(t *testing.T) {
		if results, err := Users(form.SearchUsers{Count: 100, Query: "10000023", Order: sortby.CreatedAt}); err != nil {
			t.Fatal(err)
		} else {
			// t.Logf("users: %#v", results)
			assert.LessOrEqual(t, 1, len(results))
			if len(results) > 0 {
				assert.Equal(t, 10000023, results[0].ID)
			}
		}
	})
	t.Run("SearchUid", func(t *testing.T) {
		if results, err := Users(form.SearchUsers{Count: 100, Query: "uqxqg7i1kperxvu7", Order: sortby.UpdatedAt}); err != nil {
			t.Fatal(err)
		} else {
			// t.Logf("users: %#v", results)
			assert.LessOrEqual(t, 1, len(results))
			if len(results) > 0 {
				assert.Equal(t, "uqxqg7i1kperxvu7", results[0].UserUID)
			}
		}
	})
}
