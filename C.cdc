import I from 0xf8d6e0586b0a20c7

access(all) contract C: I {
    access(all) let a: {Int: Int}

    access(all) fun f(a: Int) {
        self.a.remove(key: a)
    }

    init() {
        self.a = {
            1: 1,
            2: 2,
            3: 3,
            4: 4,
            5: 5
        }
    }
}