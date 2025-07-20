var _countryCode = null;
var _holidaysCache = {};

function getCountryCode(callback) {
    if (_countryCode) {
        callback(_countryCode);
        return;
    }
    var xhr = new XMLHttpRequest();
    xhr.open("GET", "http://ip-api.com/json/", true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
            var response = JSON.parse(xhr.responseText);
            _countryCode = response.countryCode;
            callback(_countryCode);
        }
    }
    xhr.send();
}

function getHolidays(year, countryCode, callback) {
    var cacheKey = year + "-" + countryCode;
    if (_holidaysCache[cacheKey]) {
        callback(_holidaysCache[cacheKey]);
        return;
    }
    var url = "https://date.nager.at/api/v3/PublicHolidays/" + year + "/" + countryCode;
    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
            var holidays = JSON.parse(xhr.responseText);
            _holidaysCache[cacheKey] = holidays;
            callback(holidays);
        }
    }
    xhr.send();
}

function getHolidaysForMonth(year, month, callback) {
    getCountryCode(function(countryCode) {
        getHolidays(year, countryCode, function(holidays) {
            // 0-based months (0=Jan, 11=Dec)
            var filtered = holidays.filter(function(h) {
                var date = new Date(h.date);
                return date.getFullYear() === year && date.getMonth() === month;
            });
            callback(filtered);
        });
    });
}