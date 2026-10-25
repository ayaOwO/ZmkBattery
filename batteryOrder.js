.pragma library

function ordered(batteries, order) {
    var ids = Array.isArray(order) ? order : [];
    return batteries.map((battery, index) => ({battery: battery, index: index}))
        .sort((a, b) => {
            var first = ids.indexOf(a.battery.id);
            var second = ids.indexOf(b.battery.id);
            first = first < 0 ? ids.length : first;
            second = second < 0 ? ids.length : second;
            return first - second || a.index - b.index;
        }).map(item => item.battery);
}
