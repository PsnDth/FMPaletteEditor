
class ColorParser {
    constructor (colorHex) {
        this.colorHex = colorHex;
        // Can't really do a loop here since `comp` is an rvalue
        this.b = colorHex % 256;
        colorHex = Math.floor(colorHex / 256);
        this.g = colorHex % 256;
        colorHex = Math.floor(colorHex / 256);
        this.r = colorHex % 256;
        colorHex = Math.floor(colorHex / 256);
        this.a = colorHex % 256;
        colorHex = Math.floor(colorHex / 256);
    }

    static fromARGBString(colorHex) {
        return  new ColorParser(Number(colorHex));
    }

    static RGBAtoARGBHex(r, g, b, a) {
        var colorHex = 0;
        for (const comp of [a, r, g, b]) {
            colorHex *= 256;
            colorHex += comp;
        }
        return colorHex;
    }

    static toARGB(a, r, g, b) {
        return new ColorParser(ColorParser.RGBAtoARGBHex(r, g, b, a));
    }

    get rgba() {
        return [this.r, this.g, this.b, this.a,];
    }
}

/// Using canvas doesn't seem to work on firefox, the returned colors are wrong. 
/// probably related to colorspaces but can't control it in firefox or anything either
/// and doesn't seem related to fingerprint protection (probably?)
/// Jimp seems slower/heavier but bypasses these issues
async function mask_img(img_data, palette) {
    var fastPal = new Map();
    for (const [src_color, dest_color] of palette.colors()) {
        fastPal.set(Number(src_color), ColorParser.fromARGBString(dest_color));
    }
    const img = await Jimp.read(img_data);
    return new Promise((resolve, reject) => {
        let pixels = img.bitmap.data;
        img.scan(0, 0, img.bitmap.width, img.bitmap.height, (_x, _y, i) => {
            const srcColor = ColorParser.RGBAtoARGBHex(...pixels.slice(i, i+4));
            const parser = fastPal.get(srcColor);
            if (parser == null) return;
            pixels[i] = parser.r;
            pixels[i+1] = parser.g;
            pixels[i+2] = parser.b;
            pixels[i+3] = parser.a;
        });
        img.getBase64(Jimp.AUTO, (err, url) => {
            if (err !== null) return reject(err);
            resolve(url);
        });
    });
}

async function applyForFolder(dirHandle, func) {
    allRet = [];
    for await (const entry of dirHandle.values()) {
        if (entry.kind == 'file') {
            allRet.push(await func(entry));
        }
        else if (entry.kind == 'directory') {
            // recursion should be optional and have a max depth
            allRet = allRet.concat(await applyForFolder(entry, func));
        }
    }
    return allRet;
}

class Costume {
    constructor(obj, id, name) {
        this.obj = obj; // parent object
        this.id = id;
        this.name = name;
        this.enabled = true;
        this.color_map = new Map();
    }

    
    setId(id) {
        this.obj.set(id, this.obj.delete(this.id));
        this.id = id;
    }

    getName() { return this.name; }

    colors() { return this.color_map; }
    set(src_color, dst_color) {
        this.color_map.set(src_color, dst_color);
    }
    get(src_color) {
        return this.color_map.get(src_color);
    }

    toggleEnabled() { this.enabled = !this.enabled; }
    isEnabled() { return this.enabled; }
}

class GameObject {
    constructor(palettes, id, imageAsset) {
        this.palettes = palettes; // parent object
        this.id = id;
        this.costume_map = new Map();
        this.imageAsset = imageAsset;
    }

    async getImage() {
        const img_reader = new FileReader(); 
        const img_file = await this.imageAsset.getFile();
        return new Promise((resolve, reject) => {
            img_reader.onload = (e) => resolve(e.target.result);
            img_reader.onerror = reject;
            img_reader.readAsArrayBuffer(img_file);
        });

    }

    setId(id) {
        this.palettes.set(id, this.palettes.get(this.id));
        this.palettes.delete(this.id);
        this.id = id;
    }
    empty() {
        if ( this.costumes().size == 0) return true;
        for (const [_, costume] of this.costumes()) {
            if (costume.isEnabled()) return false;
        }
        return true;
    }
    hasValidId() {
        return this.id.match(/^\w+::\w+\.\w+$/) !== null;
    }
    isExportable() {
        // Consider empty ones valid no matter what
        return this.empty() || this.hasValidId();
    }

    costumes() { return this.costume_map; }
    set(costume_id, costume_obj) {
        this.costume_map.set(costume_id, costume_obj);
    }
    get(costume_id) {
        return this.costume_map.get(costume_id);
    }
    delete(costume_id) {
        if (!this.costume_map.has(costume_id)) return undefined; 
        const costume_obj = this.get(costume_id);
        this.costume_map.delete(costume_id);
        return costume_obj;
    }
}

class ColorMap {
    constructor() {
        this.color_map = new Map();
        this.enabled = true;
    }

}

class PaletteRegistry {
    constructor() {
        // maps guid to
        this.palette_guids = [];
        this.guid_to_obj = new Map();
        this.name_to_handle = new Map();
        this.name_to_guid = new Map();
        this.palettes = null;
    }

    async addFile(file_handle) {
        const HAS_GUID_INFO = /.+(\.palettes|\.\w+\.meta)$/;
        const no_guid_info = file_handle.name.match(HAS_GUID_INFO) === null;
        if (no_guid_info) {
            if (this.name_to_guid.has(file_handle.name)) {
                this.guid_to_obj.set(
                    this.name_to_guid.get(file_handle.name),
                    file_handle
                );
                this.name_to_guid.delete(file_handle.name);
            } else {
                this.name_to_handle.set(file_handle.name, file_handle);
            }
        } else {
            const is_meta = file_handle.name.endsWith(".meta");
            const read_handle = await file_handle.getFile();
            const guid = JSON.parse(await read_handle.text()).guid;
            if (is_meta) {
                const orig_file = file_handle.name.replace(/\.meta$/, '');
                if (this.name_to_handle.has(orig_file)) {
                    this.guid_to_obj.set(
                        guid,
                        this.name_to_handle.get(orig_file)
                    );
                    this.name_to_handle.delete(orig_file);
                } else {
                    this.name_to_guid.set(orig_file, guid);
                }
            } else {
                // is palette
                this.palette_guids.push(guid);
                this.guid_to_obj.set(guid, file_handle);
            }
        }
    }

    check_invalid() {
        for (const key of this.name_to_handle.keys()) {
            if (key.endsWith(".md") || key.endsWith(".fraytools")) {
                this.name_to_handle.delete(key);
            }
        }
        this.name_to_handle.delete("README.md");
        
        if (this.name_to_handle.size != 0) {
            console.error(`Found files with no GUID`);
            console.table(this.name_to_handle);
            return false;
        }
        if (this.name_to_guid.size != 0) {
            console.error(`Found meta files with no associated content`);
            console.table(this.name_to_guid);
            return false;
        }
        return true;
    }

    async loadProject(dir_handle) {
        await applyForFolder(dir_handle, this.addFile.bind(this));
        this.check_invalid();
        const palettes = new Map();
        for (const guid of this.palette_guids) {
            const palette_file_handle = this.guid_to_obj.get(guid);
            const palette_read_handle = await palette_file_handle.getFile();
            const palette = JSON.parse(await palette_read_handle.text());
            
            const img_asset = this.guid_to_obj.get(palette.imageAsset);
            const id = palette.id;
            const costumes = new GameObject(palettes, id, img_asset);

            const id_to_color = new Map();
            for (const color_info of palette.colors) {
                id_to_color.set(color_info["$id"], color_info.color);
            }

            for (const [idx, palette_map] of palette.maps.entries()) {
                var curr_costume = new Costume(costumes, idx, palette_map.name);
                // Just mark as disabled
                const has_metadata = palette_map.pluginMetadata && palette_map.pluginMetadata["com.fraymakers.FraymakersMetadata"];
                if (has_metadata && palette_map.pluginMetadata["com.fraymakers.FraymakersMetadata"].isBase) curr_costume.toggleEnabled();
                for (const mapping of palette_map.colors) {
                    curr_costume.set(
                        id_to_color.get(mapping.paletteColorId),
                        mapping.targetColor
                    ); // NOTE: These are strings
                }
                costumes.set(idx, curr_costume);
            }
            palettes.set(id, costumes);
        }
        this.palettes = palettes;
        return this;
    }

    loaded() { return this.palettes !== null; }

    async render() {
        if (!this.loaded()) return Promise.reject(`Attempting to render before project loaded. palettes.`);

        var export_proj = new ProjectBuilder(this.palettes);
        export_proj.loadTemplateProject();

        const palette_all_area = document.getElementById("palette-all").content.cloneNode(true);
        const palette_obj_area = document.getElementById("palette-obj").content;
        const palette_costume_area = document.getElementById("palette-costume").content;
        const all_objs = new DocumentFragment();
        for await (const [id, obj] of this.palettes) {
            const curr_obj_area = palette_obj_area.cloneNode(true);
            const id_input = curr_obj_area.querySelector("input.obj_id");
            const error_marker = curr_obj_area.querySelector(".obj_error");
            id_input.value = id;
            id_input.parentNode.dataset.value = id;
            error_marker.classList.toggle("hidden", obj.hasValidId());
            id_input.addEventListener("input", () => {
                obj.setId(id_input.value);
                error_marker.classList.toggle("hidden", obj.hasValidId());
            });
            const img_data = await obj.getImage();
            const all_costumes = new DocumentFragment();
            if (obj.costumes().size == 0) continue;
            for await (const [costume_id, palette] of obj.costumes()) {
                const curr_costume_area = palette_costume_area.cloneNode(true);
                const img_elem = curr_costume_area.querySelector("img");
                const img_url = await mask_img(img_data, palette);
                img_elem.src = img_url;
                img_elem.alt = `${palette.id} ${palette.getName()}`
                
                const id_input = curr_costume_area.querySelector(".costume_idx");
                id_input.value = costume_id;
                id_input.parentNode.dataset.value = costume_id + "|";
                id_input.addEventListener("input", (e) => {
                    // Get next valid value
                    var new_val = Number(id_input.value);
                    while (obj.costumes().has(new_val)) new_val++;
                    palette.setId(new_val);
                    id_input.value = new_val;
                    id_input.parentNode.dataset.value = new_val + "|";
                });
                
                const enable_input = curr_costume_area.querySelector(".visibility");
                if (!palette.isEnabled()) enable_input.textContent += "_off";
                enable_input.addEventListener("click", (e) => {
                    enable_input.textContent = "visibility"; 
                    palette.toggleEnabled();
                    if (!palette.isEnabled()) enable_input.textContent += "_off";
                });
                // Update costume id
                all_costumes.appendChild(curr_costume_area);
            }
            curr_obj_area.querySelector(`slot[name="palette-costumes"]`).replaceWith(all_costumes);
            all_objs.appendChild(curr_obj_area);
        }
        palette_all_area.querySelector(`slot[name="palette-objs"]`).replaceWith(all_objs);
        palette_all_area.querySelector(`.export`).addEventListener("click", (e) => {
            var invalid_ids = [];
            for (const [id, obj] of this.palettes) {
                if (!obj.isExportable())  {
                    invalid_ids.push(id);
                }
            }
            const result_box = document.getElementById("result");
            if (invalid_ids.length) {
                result_box.classList = "desc error_resp";
                result_box.textContent = `Not exporting due to invalid IDs for: ${invalid_ids}`;
                result_box.scrollIntoView({ behavior: "smooth", block: "center" });
                return;
            }
            result_box.classList = "desc";
            // TODO: Can we just put this in the fraytools project? or use that as the default? idk
            // export_proj.setId(new_id);
            // export_proj.setName(new_name);
            export_proj.downloadProject();
        });
        document.querySelector(".palettes").replaceWith(palette_all_area);
    }


}

class ProjectBuilder {
static CMAP_TEMPLATE = `    $src_color => $dest_color,`;
static PMAP_TEMPLATE = `  "$unsafe_id" => $safe_id_PALETTES,`;
static COSTUME_TEMPLATE = `  $costume_id => [
$cmap_list
  ],`;
static PALETTE_TEMPLATE = `var $safe_id_PALETTES = [
$costume_list
];
`;
static SCRIPT_TEMPLATE = `$palette_list
    
var PALETTES = [
$pmap_list  
];`;
    static TEMPLATE_URL = "https://raw.githubusercontent.com/PsnDth/FMPaletteEditor/main/build/paletteeditor.fra"
    static TEMPLATE_STRING = `/*CUSTOM_PALETTE_INFO*/`;
    constructor (palettes) {
        this.id = null;
        this.name = null;
        this.palettes = palettes;

        this.raw_project = null;
        this.project = null;
    }

    setId(id) { this.id = id; }
    setName(name) { this.name = name; }

    /**
     * Can call early so to save it in memory, while other stuff are going on
     */
    loadTemplateProject() {
        this.project = new Promise((resolve, reject) => {
            if (this.raw_project !== null) return resolve(this.raw_project);
            resolve(fetch(ProjectBuilder.TEMPLATE_URL).then((resp) => {
                if (!(resp.status == 200 || resp.status == 0)) 
                    return Promise.reject(new Error(`${resp.status} w/ ${resp.statusText}`));
                this.raw_project = resp.arrayBuffer();
                return this.raw_project;
            }));
        }); 
    }

    async downloadProject() {
        const template_proj = await this.project;
        // copy the project
        const new_proj_contents = template_proj.slice(0);
        const new_proj = new DataView(new_proj_contents);
        const text_decoder = new TextDecoder();
        const text_encoder = new TextEncoder();
        // First 4 bytes are size of json
        const JSON_HEADER_SIZE = 4;
        var json_num_bytes = new_proj.getUint32(0, false /* big endian */);
        const json_contents = text_decoder.decode(new_proj.buffer.slice(JSON_HEADER_SIZE, json_num_bytes + JSON_HEADER_SIZE));

        const id = this.id || "paletteeditor";
        const name = this.name || "Palette Editor";
        // stringify as json string amdremove wrapping quotation marks
        const palette_script = JSON.stringify(this.fillTemplate()).slice(1, -1);
        const new_json_contents =  json_contents.replace(ProjectBuilder.TEMPLATE_STRING, palette_script)
                                       .replaceAll("paletteeditor", id)
                                       .replaceAll("Palette Editor", name);
        
        const new_json_bytes = text_encoder.encode(new_json_contents);
        new_proj.setUint32(0, new_json_bytes.byteLength, false /* big endian */);
        console.log(new_proj.getUint32(0, false));
        saveAs(new Blob([
            // new header with fixed size
            new_proj.buffer.slice(0, JSON_HEADER_SIZE), 
            // new data (updated id, name and script contents)
            new_json_bytes, 
            // same image data as before
            new_proj.buffer.slice(json_num_bytes + JSON_HEADER_SIZE)
        ], {type: "application/octet-stream"}), `${id}.fra`);
    }
    fillTemplate() {
        const pmap_list = [];
        const palette_list =[];
        for (const [obj_id, obj] of this.palettes) {
            if (obj.costumes().size == 0) continue; // skip empty maps
            const safe_id = obj_id.replace(/(\w+)::(\w+).(\w+)/, "$1__$2_$3");
            const costume_list = [];
            for (const [costume_id, costume] of obj.costumes()) {
                if (!costume.isEnabled()) {
                    console.log(`Skipping costume ${costume.getName()} from ${obj_id} because it is disabled`);
                    continue;
                }

                const cmap_list = [];
                for (const [src_color, dest_color] of costume.colors()) {
                    cmap_list.push(ProjectBuilder.CMAP_TEMPLATE.replace("$src_color", src_color).replace("$dest_color", dest_color));
                }
                costume_list.push(ProjectBuilder.COSTUME_TEMPLATE.replace("$cmap_list", cmap_list.join("\n")).replace("$costume_id", costume_id));
            }
            if (costume_list.length == 0) continue; // skip empty maps
            pmap_list.push(ProjectBuilder.PMAP_TEMPLATE.replace("$unsafe_id", obj_id).replace("$safe_id", safe_id));
            palette_list.push(ProjectBuilder.PALETTE_TEMPLATE.replace("$costume_list", costume_list.join("\n")).replace("$safe_id", safe_id));
        }
        return ProjectBuilder.SCRIPT_TEMPLATE.replace("$palette_list", palette_list.join("\n")).replace("$pmap_list", pmap_list.join("\n"));
    }
}

async function handleNewFolder(dirHandle) {
    // first clear the current palettes and write a loading message
    const result_box = document.getElementById("result");
    return new Promise((resolve, reject) => {
        document.querySelector(".palettes").innerHTML = "";
        result_box.classList = "desc info_resp";
        result_box.textContent = "Loading palette information ...";
        resolve();
    }).then(() => {
        const registry = new PaletteRegistry();
        return registry.loadProject(dirHandle);
    }).then((registry) => {
        return registry.render();
    }).then(() => {
        // clear message
        result_box.classList = "desc";
    }).catch( (err) => {
        if (!(err instanceof DOMException && err.name == "AbortError")) {
            result_box.textContent = `Failed to process project. Reason: ${err}`;
        } else {
            result_box.textContent = "Couldn't open provided folder, or folder does not have a .fraytools file. Please try again.";
        }
        result_box.classList = "desc error_resp";
        console.error(`Failed to apply to folder. Reason: ${err}`);
    });
}


async function getDraggedFolder(items) {
    if (items.length == 1) {
        const item = items[0];
        if (item.kind == "file") {
            const entry = await item.getAsFileSystemHandle();
            if (entry.kind === "directory") return entry;
        }
    } 
    throw "Dragged input did not match expectations. Must be a single directory with a .fraytools file.";
}

/**
 * TODO:
 * - Input fields for name/ID of returned project
 * - Loading message while project is being processed 
 * - Speed up render process
 *     - Should render with just the regular image first and then swap in the palette applied image when it's ready
 */

window.addEventListener("load", (e) => {
    
    const result_box = document.getElementById("result");
    const start_button = document.getElementById("start_process");
    const can_modify_fs = ("showDirectoryPicker"  in window);
    if (!can_modify_fs) {
        start_button.disabled = true;
        result_box.textContent = "Can't access the filesystem directly with this browser 😢. Try using something chromium ...";
        result_box.classList = "desc error_resp";
        console.error(`showDirectoryPicker is not supported in this browser`);
        return;
    }
    start_button.addEventListener("click", async (event) => {
        window.showDirectoryPicker({ id: "ft_folder", mode: "read" }).then(handleNewFolder);
    });
    document.addEventListener("dragover", (e) => { e.preventDefault(); });
    document.addEventListener("drop", async (e) => {
        e.preventDefault();
        getDraggedFolder(e.dataTransfer.items).then(handleNewFolder);
    });
});