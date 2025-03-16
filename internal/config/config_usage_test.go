package config

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/photoprism/photoprism/pkg/fs"
	"github.com/photoprism/photoprism/pkg/fs/duf"
)

func TestConfig_Usage(t *testing.T) {
	c := TestConfig()

	FlushUsageCache()
	c.options.UsageInfo = true
	result := c.Usage()
	assert.GreaterOrEqual(t, result.FilesUsed, uint64(60000000))

	t.Logf("Storage Used: %d MB (%d%%), Free: %d MB (%d%%), Total %d MB", result.FilesUsed/duf.MB, result.FilesUsedPct, result.FilesFree/duf.MB, result.FilesFreePct, result.FilesTotal/duf.MB)

	c.options.FilesQuota = uint64(1)
	result2 := c.Usage()

	t.Logf("Storage Used: %d MB (%d%%), Free: %d MB (%d%%), Total %d MB", result2.FilesUsed/duf.MB, result2.FilesUsedPct, result2.FilesFree/duf.MB, result2.FilesFreePct, result2.FilesTotal/duf.MB)

	//result cached
	assert.GreaterOrEqual(t, result2.FilesUsed, uint64(60000000))
	assert.GreaterOrEqual(t, result2.FilesTotal, uint64(60000000))

	FlushUsageCache()
	result3 := c.Usage()

	t.Logf("Storage Used: %d MB (%d%%), Free: %d MB (%d%%), Total %d MB", result3.FilesUsed/duf.MB, result3.FilesUsedPct, result3.FilesFree/duf.MB, result3.FilesFreePct, result3.FilesTotal/duf.MB)

	assert.GreaterOrEqual(t, result3.FilesUsed, uint64(60000000))
	assert.GreaterOrEqual(t, result3.FilesTotal, uint64(18))

	c.options.UsageInfo = false
	c.options.FilesQuota = uint64(0)
	assert.Equal(t, c.Usage().FilesUsed, uint64(0))
}

func TestConfig_Quota(t *testing.T) {
	c := TestConfig()

	FlushUsageCache()
	assert.Equal(t, uint64(0), c.FilesQuota())
	assert.Equal(t, 0, c.UsersQuota())

	c.options.FilesQuota = uint64(1)
	c.options.UsersQuota = 10

	assert.Equal(t, uint64(1), c.FilesQuota())
	assert.Equal(t, uint64(fs.GB), c.FilesQuotaBytes())
	assert.Equal(t, 10, c.UsersQuota())

	c.options.FilesQuota = uint64(0)
	c.options.UsersQuota = 0
}

func TestConfig_FilesQuotaExceeded(t *testing.T) {
	c := TestConfig()

	FlushUsageCache()
	assert.False(t, c.FilesQuotaExceeded())

	c.options.FilesQuota = uint64(1)
	FlushUsageCache()
	assert.True(t, c.FilesQuotaExceeded())

	c.options.FilesQuota = uint64(5)
	FlushUsageCache()
	assert.False(t, c.FilesQuotaExceeded())

	c.options.FilesQuota = uint64(0)
}

func TestConfig_UsersQuotaExceeded(t *testing.T) {
	c := TestConfig()

	FlushUsageCache()
	assert.False(t, c.UsersQuotaExceeded())

	c.options.UsersQuota = 1
	FlushUsageCache()
	assert.True(t, c.UsersQuotaExceeded())

	c.options.UsersQuota = 100000
	FlushUsageCache()
	assert.False(t, c.UsersQuotaExceeded())

	c.options.UsersQuota = 0
}
