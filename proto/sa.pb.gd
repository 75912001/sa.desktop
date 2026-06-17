extends Node

#
# BSD 3-Clause License
#
# Copyright (c) 2018 - 2026, Oleg Malyavkin
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# DEBUG_TAB redefine this "  " if you need, example: const DEBUG_TAB = "\t"

const PROTO_VERSION = 3

const DEBUG_TAB : String = "  "

enum PB_ERR {
	NO_ERRORS = 0,
	VARINT_NOT_FOUND = -1,
	REPEATED_COUNT_NOT_FOUND = -2,
	REPEATED_COUNT_MISMATCH = -3,
	LENGTHDEL_SIZE_NOT_FOUND = -4,
	LENGTHDEL_SIZE_MISMATCH = -5,
	PACKAGE_SIZE_MISMATCH = -6,
	UNDEFINED_STATE = -7,
	PARSE_INCOMPLETE = -8,
	REQUIRED_FIELDS = -9
}

enum PB_DATA_TYPE {
	INT32 = 0,
	SINT32 = 1,
	UINT32 = 2,
	INT64 = 3,
	SINT64 = 4,
	UINT64 = 5,
	BOOL = 6,
	ENUM = 7,
	FIXED32 = 8,
	SFIXED32 = 9,
	FLOAT = 10,
	FIXED64 = 11,
	SFIXED64 = 12,
	DOUBLE = 13,
	STRING = 14,
	BYTES = 15,
	MESSAGE = 16,
	MAP = 17
}

const DEFAULT_VALUES_2 = {
	PB_DATA_TYPE.INT32: null,
	PB_DATA_TYPE.SINT32: null,
	PB_DATA_TYPE.UINT32: null,
	PB_DATA_TYPE.INT64: null,
	PB_DATA_TYPE.SINT64: null,
	PB_DATA_TYPE.UINT64: null,
	PB_DATA_TYPE.BOOL: null,
	PB_DATA_TYPE.ENUM: null,
	PB_DATA_TYPE.FIXED32: null,
	PB_DATA_TYPE.SFIXED32: null,
	PB_DATA_TYPE.FLOAT: null,
	PB_DATA_TYPE.FIXED64: null,
	PB_DATA_TYPE.SFIXED64: null,
	PB_DATA_TYPE.DOUBLE: null,
	PB_DATA_TYPE.STRING: null,
	PB_DATA_TYPE.BYTES: null,
	PB_DATA_TYPE.MESSAGE: null,
	PB_DATA_TYPE.MAP: null
}

const DEFAULT_VALUES_3 = {
	PB_DATA_TYPE.INT32: 0,
	PB_DATA_TYPE.SINT32: 0,
	PB_DATA_TYPE.UINT32: 0,
	PB_DATA_TYPE.INT64: 0,
	PB_DATA_TYPE.SINT64: 0,
	PB_DATA_TYPE.UINT64: 0,
	PB_DATA_TYPE.BOOL: false,
	PB_DATA_TYPE.ENUM: 0,
	PB_DATA_TYPE.FIXED32: 0,
	PB_DATA_TYPE.SFIXED32: 0,
	PB_DATA_TYPE.FLOAT: 0.0,
	PB_DATA_TYPE.FIXED64: 0,
	PB_DATA_TYPE.SFIXED64: 0,
	PB_DATA_TYPE.DOUBLE: 0.0,
	PB_DATA_TYPE.STRING: "",
	PB_DATA_TYPE.BYTES: [],
	PB_DATA_TYPE.MESSAGE: null,
	PB_DATA_TYPE.MAP: []
}

enum PB_TYPE {
	VARINT = 0,
	FIX64 = 1,
	LENGTHDEL = 2,
	STARTGROUP = 3,
	ENDGROUP = 4,
	FIX32 = 5,
	UNDEFINED = 8
}

enum PB_RULE {
	OPTIONAL = 0,
	REQUIRED = 1,
	REPEATED = 2,
	RESERVED = 3
}

enum PB_SERVICE_STATE {
	FILLED = 0,
	UNFILLED = 1
}

class PBField:
	extends RefCounted
	func _init(a_name : String, a_type : int, a_rule : int, a_tag : int, packed : bool, a_value = null):
		name = a_name
		type = a_type
		rule = a_rule
		tag = a_tag
		option_packed = packed
		value = a_value
		
	var name : String
	var type : int
	var rule : int
	var tag : int
	var option_packed : bool
	var value
	var is_map_field : bool = false
	var option_default : bool = false

class PBTypeTag:
	extends RefCounted
	var ok : bool = false
	var type : int
	var tag : int
	var offset : int

class PBServiceField:
	extends RefCounted
	var field : PBField
	var func_ref = null
	var state : int = PB_SERVICE_STATE.UNFILLED

class PBPacker:
	static func convert_signed(n : int) -> int:
		if n < -2147483648:
			return (n << 1) ^ (n >> 63)
		else:
			return (n << 1) ^ (n >> 31)

	static func deconvert_signed(n : int) -> int:
		if n & 0x01:
			return ~(n >> 1)
		else:
			return (n >> 1)

	static func pack_varint(value) -> PackedByteArray:
		var varint : PackedByteArray = PackedByteArray()
		if typeof(value) == TYPE_BOOL:
			if value:
				value = 1
			else:
				value = 0
		for _i in range(9):
			var b = value & 0x7F
			value >>= 7
			if value:
				varint.append(b | 0x80)
			else:
				varint.append(b)
				break
		if varint.size() == 9 && (varint[8] & 0x80 != 0):
			varint.append(0x01)
		return varint

	static func pack_bytes(value, count : int, data_type : int) -> PackedByteArray:
		var bytes : PackedByteArray = PackedByteArray()
		if data_type == PB_DATA_TYPE.FLOAT:
			var spb : StreamPeerBuffer = StreamPeerBuffer.new()
			spb.put_float(value)
			bytes = spb.get_data_array()
		elif data_type == PB_DATA_TYPE.DOUBLE:
			var spb : StreamPeerBuffer = StreamPeerBuffer.new()
			spb.put_double(value)
			bytes = spb.get_data_array()
		else:
			for _i in range(count):
				bytes.append(value & 0xFF)
				value >>= 8
		return bytes

	static func unpack_bytes(bytes : PackedByteArray, index : int, count : int, data_type : int):
		if data_type == PB_DATA_TYPE.FLOAT:
			return bytes.decode_float(index)
		elif data_type == PB_DATA_TYPE.DOUBLE:
			return bytes.decode_double(index)
		elif data_type == PB_DATA_TYPE.FIXED32:
			return bytes.decode_u32(index)
		elif data_type == PB_DATA_TYPE.SFIXED32:
			return bytes.decode_s32(index)
		elif data_type == PB_DATA_TYPE.FIXED64:
			return bytes.decode_u64(index)
		elif data_type == PB_DATA_TYPE.SFIXED64:
			return bytes.decode_s64(index)
		else:
			var value : int = 0
			for i in range(count):
				value |= bytes[index + i] << (8 * i)
			return value

	static func unpack_varint(varint_bytes) -> int:
		var value : int = 0
		var i: int = varint_bytes.size() - 1
		while i > -1:
			value = (value << 7) | (varint_bytes[i] & 0x7F)
			i -= 1
		return value

	static func pack_type_tag(type : int, tag : int) -> PackedByteArray:
		return pack_varint((tag << 3) | type)

	static func isolate_varint(bytes : PackedByteArray, index : int) -> PackedByteArray:
		var i: int = index
		while i <= index + 10 && i < bytes.size(): # Protobuf varint max size is 10 bytes
			if !(bytes[i] & 0x80):
				return bytes.slice(index, i + 1)
			i += 1
		return [] # Unreachable

	static func unpack_type_tag(bytes : PackedByteArray, index : int) -> PBTypeTag:
		var varint_bytes : PackedByteArray = isolate_varint(bytes, index)
		var result : PBTypeTag = PBTypeTag.new()
		if varint_bytes.size() != 0:
			result.ok = true
			result.offset = varint_bytes.size()
			var unpacked : int = unpack_varint(varint_bytes)
			result.type = unpacked & 0x07
			result.tag = unpacked >> 3
		return result

	static func pack_length_delimeted(type : int, tag : int, bytes : PackedByteArray) -> PackedByteArray:
		var result : PackedByteArray = pack_type_tag(type, tag)
		result.append_array(pack_varint(bytes.size()))
		result.append_array(bytes)
		return result

	static func pb_type_from_data_type(data_type : int) -> int:
		if data_type == PB_DATA_TYPE.INT32 || data_type == PB_DATA_TYPE.SINT32 || data_type == PB_DATA_TYPE.UINT32 || data_type == PB_DATA_TYPE.INT64 || data_type == PB_DATA_TYPE.SINT64 || data_type == PB_DATA_TYPE.UINT64 || data_type == PB_DATA_TYPE.BOOL || data_type == PB_DATA_TYPE.ENUM:
			return PB_TYPE.VARINT
		elif data_type == PB_DATA_TYPE.FIXED32 || data_type == PB_DATA_TYPE.SFIXED32 || data_type == PB_DATA_TYPE.FLOAT:
			return PB_TYPE.FIX32
		elif data_type == PB_DATA_TYPE.FIXED64 || data_type == PB_DATA_TYPE.SFIXED64 || data_type == PB_DATA_TYPE.DOUBLE:
			return PB_TYPE.FIX64
		elif data_type == PB_DATA_TYPE.STRING || data_type == PB_DATA_TYPE.BYTES || data_type == PB_DATA_TYPE.MESSAGE || data_type == PB_DATA_TYPE.MAP:
			return PB_TYPE.LENGTHDEL
		else:
			return PB_TYPE.UNDEFINED

	static func pack_field(field : PBField) -> PackedByteArray:
		var type : int = pb_type_from_data_type(field.type)
		var type_copy : int = type
		if field.rule == PB_RULE.REPEATED && field.option_packed:
			type = PB_TYPE.LENGTHDEL
		var head : PackedByteArray = pack_type_tag(type, field.tag)
		var data : PackedByteArray = PackedByteArray()
		if type == PB_TYPE.VARINT:
			var value
			if field.rule == PB_RULE.REPEATED:
				for v in field.value:
					data.append_array(head)
					if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
						value = convert_signed(v)
					else:
						value = v
					data.append_array(pack_varint(value))
				return data
			else:
				if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
					value = convert_signed(field.value)
				else:
					value = field.value
				data = pack_varint(value)
		elif type == PB_TYPE.FIX32:
			if field.rule == PB_RULE.REPEATED:
				for v in field.value:
					data.append_array(head)
					data.append_array(pack_bytes(v, 4, field.type))
				return data
			else:
				data.append_array(pack_bytes(field.value, 4, field.type))
		elif type == PB_TYPE.FIX64:
			if field.rule == PB_RULE.REPEATED:
				for v in field.value:
					data.append_array(head)
					data.append_array(pack_bytes(v, 8, field.type))
				return data
			else:
				data.append_array(pack_bytes(field.value, 8, field.type))
		elif type == PB_TYPE.LENGTHDEL:
			if field.rule == PB_RULE.REPEATED:
				if type_copy == PB_TYPE.VARINT:
					if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
						var signed_value : int
						for v in field.value:
							signed_value = convert_signed(v)
							data.append_array(pack_varint(signed_value))
					else:
						for v in field.value:
							data.append_array(pack_varint(v))
					return pack_length_delimeted(type, field.tag, data)
				elif type_copy == PB_TYPE.FIX32:
					for v in field.value:
						data.append_array(pack_bytes(v, 4, field.type))
					return pack_length_delimeted(type, field.tag, data)
				elif type_copy == PB_TYPE.FIX64:
					for v in field.value:
						data.append_array(pack_bytes(v, 8, field.type))
					return pack_length_delimeted(type, field.tag, data)
				elif field.type == PB_DATA_TYPE.STRING:
					for v in field.value:
						var obj = v.to_utf8_buffer()
						data.append_array(pack_length_delimeted(type, field.tag, obj))
					return data
				elif field.type == PB_DATA_TYPE.BYTES:
					for v in field.value:
						data.append_array(pack_length_delimeted(type, field.tag, v))
					return data
				elif typeof(field.value[0]) == TYPE_OBJECT:
					for v in field.value:
						var obj : PackedByteArray = v.to_bytes()
						data.append_array(pack_length_delimeted(type, field.tag, obj))
					return data
			else:
				if field.type == PB_DATA_TYPE.STRING:
					var str_bytes : PackedByteArray = field.value.to_utf8_buffer()
					if PROTO_VERSION == 2 || (PROTO_VERSION == 3 && str_bytes.size() > 0):
						data.append_array(str_bytes)
						return pack_length_delimeted(type, field.tag, data)
				if field.type == PB_DATA_TYPE.BYTES:
					if PROTO_VERSION == 2 || (PROTO_VERSION == 3 && field.value.size() > 0):
						data.append_array(field.value)
						return pack_length_delimeted(type, field.tag, data)
				elif typeof(field.value) == TYPE_OBJECT:
					var obj : PackedByteArray = field.value.to_bytes()
					if obj.size() > 0:
						data.append_array(obj)
					return pack_length_delimeted(type, field.tag, data)
				else:
					pass
		if data.size() > 0:
			head.append_array(data)
			return head
		else:
			return data

	static func skip_unknown_field(bytes : PackedByteArray, offset : int, type : int) -> int:
		if type == PB_TYPE.VARINT:
			return offset + isolate_varint(bytes, offset).size()
		if type == PB_TYPE.FIX64:
			return offset + 8
		if type == PB_TYPE.LENGTHDEL:
			var length_bytes : PackedByteArray = isolate_varint(bytes, offset)
			var length : int = unpack_varint(length_bytes)
			return offset + length_bytes.size() + length
		if type == PB_TYPE.FIX32:
			return offset + 4
		return PB_ERR.UNDEFINED_STATE

	static func unpack_field(bytes : PackedByteArray, offset : int, field : PBField, type : int, message_func_ref) -> int:
		if field.rule == PB_RULE.REPEATED && type != PB_TYPE.LENGTHDEL && field.option_packed:
			var count = isolate_varint(bytes, offset)
			if count.size() > 0:
				offset += count.size()
				count = unpack_varint(count)
				if type == PB_TYPE.VARINT:
					var val
					var counter = offset + count
					while offset < counter:
						val = isolate_varint(bytes, offset)
						if val.size() > 0:
							offset += val.size()
							val = unpack_varint(val)
							if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
								val = deconvert_signed(val)
							elif field.type == PB_DATA_TYPE.BOOL:
								if val:
									val = true
								else:
									val = false
							field.value.append(val)
						else:
							return PB_ERR.REPEATED_COUNT_MISMATCH
					return offset
				elif type == PB_TYPE.FIX32 || type == PB_TYPE.FIX64:
					var type_size
					if type == PB_TYPE.FIX32:
						type_size = 4
					else:
						type_size = 8
					var val
					var counter = offset + count
					while offset < counter:
						if (offset + type_size) > bytes.size():
							return PB_ERR.REPEATED_COUNT_MISMATCH
						val = unpack_bytes(bytes, offset, type_size, field.type)
						offset += type_size
						field.value.append(val)
					return offset
			else:
				return PB_ERR.REPEATED_COUNT_NOT_FOUND
		else:
			if type == PB_TYPE.VARINT:
				var val = isolate_varint(bytes, offset)
				if val.size() > 0:
					offset += val.size()
					val = unpack_varint(val)
					if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
						val = deconvert_signed(val)
					elif field.type == PB_DATA_TYPE.BOOL:
						if val:
							val = true
						else:
							val = false
					if field.rule == PB_RULE.REPEATED:
						field.value.append(val)
					else:
						field.value = val
				else:
					return PB_ERR.VARINT_NOT_FOUND
				return offset
			elif type == PB_TYPE.FIX32 || type == PB_TYPE.FIX64:
				var type_size
				if type == PB_TYPE.FIX32:
					type_size = 4
				else:
					type_size = 8
				var val
				if (offset + type_size) > bytes.size():
					return PB_ERR.REPEATED_COUNT_MISMATCH
				val = unpack_bytes(bytes, offset, type_size, field.type)
				offset += type_size
				if field.rule == PB_RULE.REPEATED:
					field.value.append(val)
				else:
					field.value = val
				return offset
			elif type == PB_TYPE.LENGTHDEL:
				var inner_size = isolate_varint(bytes, offset)
				if inner_size.size() > 0:
					offset += inner_size.size()
					inner_size = unpack_varint(inner_size)
					if inner_size >= 0:
						if inner_size + offset > bytes.size():
							return PB_ERR.LENGTHDEL_SIZE_MISMATCH
						if message_func_ref != null:
							var message = message_func_ref.call()
							if inner_size > 0:
								var sub_offset = message.from_bytes(bytes, offset, inner_size + offset)
								if sub_offset > 0:
									if sub_offset - offset >= inner_size:
										offset = sub_offset
										return offset
									else:
										return PB_ERR.LENGTHDEL_SIZE_MISMATCH
								return sub_offset
							else:
								return offset
						elif field.type == PB_DATA_TYPE.STRING:
							var str_bytes : PackedByteArray = bytes.slice(offset, inner_size + offset)
							if field.rule == PB_RULE.REPEATED:
								field.value.append(str_bytes.get_string_from_utf8())
							else:
								field.value = str_bytes.get_string_from_utf8()
							return offset + inner_size
						elif field.type == PB_DATA_TYPE.BYTES:
							var val_bytes : PackedByteArray = bytes.slice(offset, inner_size + offset)
							if field.rule == PB_RULE.REPEATED:
								field.value.append(val_bytes)
							else:
								field.value = val_bytes
							return offset + inner_size
					else:
						return PB_ERR.LENGTHDEL_SIZE_NOT_FOUND
				else:
					return PB_ERR.LENGTHDEL_SIZE_NOT_FOUND
		return PB_ERR.UNDEFINED_STATE

	static func unpack_message(data, bytes : PackedByteArray, offset : int, limit : int) -> int:
		while true:
			var tt : PBTypeTag = unpack_type_tag(bytes, offset)
			if tt.ok:
				offset += tt.offset
				if data.has(tt.tag):
					var service : PBServiceField = data[tt.tag]
					var type : int = pb_type_from_data_type(service.field.type)
					if type == tt.type || (tt.type == PB_TYPE.LENGTHDEL && service.field.rule == PB_RULE.REPEATED && service.field.option_packed):
						var res : int = unpack_field(bytes, offset, service.field, type, service.func_ref)
						if res > 0:
							service.state = PB_SERVICE_STATE.FILLED
							offset = res
							if offset == limit:
								return offset
							elif offset > limit:
								return PB_ERR.PACKAGE_SIZE_MISMATCH
						elif res < 0:
							return res
						else:
							break
				else:
					var res : int = skip_unknown_field(bytes, offset, tt.type)
					if res > 0:
						offset = res
						if offset == limit:
							return offset
						elif offset > limit:
							return PB_ERR.PACKAGE_SIZE_MISMATCH
					elif res < 0:
						return res
					else:
						break							
			else:
				return offset
		return PB_ERR.UNDEFINED_STATE

	static func pack_message(data) -> PackedByteArray:
		var DEFAULT_VALUES
		if PROTO_VERSION == 2:
			DEFAULT_VALUES = DEFAULT_VALUES_2
		elif PROTO_VERSION == 3:
			DEFAULT_VALUES = DEFAULT_VALUES_3
		var result : PackedByteArray = PackedByteArray()
		var keys : Array = data.keys()
		keys.sort()
		for i in keys:
			if data[i].field.value != null:
				if data[i].state == PB_SERVICE_STATE.UNFILLED \
				&& !data[i].field.is_map_field \
				&& typeof(data[i].field.value) == typeof(DEFAULT_VALUES[data[i].field.type]) \
				&& data[i].field.value == DEFAULT_VALUES[data[i].field.type]:
					continue
				elif data[i].field.rule == PB_RULE.REPEATED && data[i].field.value.size() == 0:
					continue
				result.append_array(pack_field(data[i].field))
			elif data[i].field.rule == PB_RULE.REQUIRED:
				print("Error: required field is not filled: Tag:", data[i].field.tag)
				return PackedByteArray()
		return result

	static func check_required(data) -> bool:
		var keys : Array = data.keys()
		for i in keys:
			if data[i].field.rule == PB_RULE.REQUIRED && data[i].state == PB_SERVICE_STATE.UNFILLED:
				return false
		return true

	static func construct_map(key_values):
		var result = {}
		for kv in key_values:
			result[kv.get_key()] = kv.get_value()
		return result
	
	static func tabulate(text : String, nesting : int) -> String:
		var tab : String = ""
		for _i in range(nesting):
			tab += DEBUG_TAB
		return tab + text
	
	static func value_to_string(value, field : PBField, nesting : int) -> String:
		var result : String = ""
		var text : String
		if field.type == PB_DATA_TYPE.MESSAGE:
			result += "{"
			nesting += 1
			text = message_to_string(value.data, nesting)
			if text != "":
				result += "\n" + text
				nesting -= 1
				result += tabulate("}", nesting)
			else:
				nesting -= 1
				result += "}"
		elif field.type == PB_DATA_TYPE.BYTES:
			result += "<"
			for i in range(value.size()):
				result += str(value[i])
				if i != (value.size() - 1):
					result += ", "
			result += ">"
		elif field.type == PB_DATA_TYPE.STRING:
			result += "\"" + value + "\""
		elif field.type == PB_DATA_TYPE.ENUM:
			result += "ENUM::" + str(value)
		else:
			result += str(value)
		return result
	
	static func field_to_string(field : PBField, nesting : int) -> String:
		var result : String = tabulate(field.name + ": ", nesting)
		if field.type == PB_DATA_TYPE.MAP:
			if field.value.size() > 0:
				result += "(\n"
				nesting += 1
				for i in range(field.value.size()):
					var local_key_value = field.value[i].data[1].field
					result += tabulate(value_to_string(local_key_value.value, local_key_value, nesting), nesting) + ": "
					local_key_value = field.value[i].data[2].field
					result += value_to_string(local_key_value.value, local_key_value, nesting)
					if i != (field.value.size() - 1):
						result += ","
					result += "\n"
				nesting -= 1
				result += tabulate(")", nesting)
			else:
				result += "()"
		elif field.rule == PB_RULE.REPEATED:
			if field.value.size() > 0:
				result += "[\n"
				nesting += 1
				for i in range(field.value.size()):
					result += tabulate(str(i) + ": ", nesting)
					result += value_to_string(field.value[i], field, nesting)
					if i != (field.value.size() - 1):
						result += ","
					result += "\n"
				nesting -= 1
				result += tabulate("]", nesting)
			else:
				result += "[]"
		else:
			result += value_to_string(field.value, field, nesting)
		result += ";\n"
		return result
		
	static func message_to_string(data, nesting : int = 0) -> String:
		var DEFAULT_VALUES
		if PROTO_VERSION == 2:
			DEFAULT_VALUES = DEFAULT_VALUES_2
		elif PROTO_VERSION == 3:
			DEFAULT_VALUES = DEFAULT_VALUES_3
		var result : String = ""
		var keys : Array = data.keys()
		keys.sort()
		for i in keys:
			if data[i].field.value != null:
				if data[i].state == PB_SERVICE_STATE.UNFILLED \
				&& !data[i].field.is_map_field \
				&& typeof(data[i].field.value) == typeof(DEFAULT_VALUES[data[i].field.type]) \
				&& data[i].field.value == DEFAULT_VALUES[data[i].field.type]:
					continue
				elif data[i].field.rule == PB_RULE.REPEATED && data[i].field.value.size() == 0:
					continue
				result += field_to_string(data[i].field, nesting)
			elif data[i].field.rule == PB_RULE.REQUIRED:
				result += data[i].field.name + ": " + "error"
		return result



############### USER DATA BEGIN ################


class AccountRecord:
	extends RefCounted
	func _init():
		var service
		
		__UsedUUID = PBField.new("UsedUUID", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
		service = PBServiceField.new()
		service.field = __UsedUUID
		data[__UsedUUID.tag] = service
		
		var __CharacterRecordMap_default: Array = []
		__CharacterRecordMap = PBField.new("CharacterRecordMap", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 10, true, __CharacterRecordMap_default)
		service = PBServiceField.new()
		service.field = __CharacterRecordMap
		service.func_ref = Callable(self, "add_empty_CharacterRecordMap")
		data[__CharacterRecordMap.tag] = service
		
	var data = {}
	
	var __UsedUUID: PBField
	func has_UsedUUID() -> bool:
		if __UsedUUID.value != null:
			return true
		return false
	func get_UsedUUID() -> int:
		return __UsedUUID.value
	func clear_UsedUUID() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__UsedUUID.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
	func set_UsedUUID(value : int) -> void:
		__UsedUUID.value = value
	
	var __CharacterRecordMap: PBField
	func get_raw_CharacterRecordMap():
		return __CharacterRecordMap.value
	func get_CharacterRecordMap():
		return PBPacker.construct_map(__CharacterRecordMap.value)
	func clear_CharacterRecordMap():
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__CharacterRecordMap.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_CharacterRecordMap() -> AccountRecord.map_type_CharacterRecordMap:
		var element = AccountRecord.map_type_CharacterRecordMap.new()
		__CharacterRecordMap.value.append(element)
		return element
	func add_CharacterRecordMap(a_key) -> CharacterRecord:
		var idx = -1
		for i in range(__CharacterRecordMap.value.size()):
			if __CharacterRecordMap.value[i].get_key() == a_key:
				idx = i
				break
		var element = AccountRecord.map_type_CharacterRecordMap.new()
		element.set_key(a_key)
		if idx != -1:
			__CharacterRecordMap.value[idx] = element
		else:
			__CharacterRecordMap.value.append(element)
		return element.new_value()
	
	class map_type_CharacterRecordMap:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			service.func_ref = Callable(self, "new_value")
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			if __key.value != null:
				return true
			return false
		func get_key() -> int:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
		func set_key(value : int) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			if __value.value != null:
				return true
			return false
		func get_value() -> CharacterRecord:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		func new_value() -> CharacterRecord:
			__value.value = CharacterRecord.new()
			return __value.value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
enum CharacterAction {
	CharacterAction_Unknow = 0,
	CharacterAction_Attack = 1,
	CharacterAction_Wave = 2,
	CharacterAction_Faint = 3,
	CharacterAction_Hurt = 4,
	CharacterAction_Defense = 5,
	CharacterAction_Sad = 6,
	CharacterAction_Angry = 7,
	CharacterAction_Sit = 8,
	CharacterAction_Stand = 9,
	CharacterAction_Throw = 10,
	CharacterAction_Nod = 11,
	CharacterAction_Walk = 12,
	CharacterAction_Happy = 13,
	CharacterAction_Max = 14
}

class CharacterRecord:
	extends RefCounted
	func _init():
		var service
		
		__UUID = PBField.new("UUID", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
		service = PBServiceField.new()
		service.field = __UUID
		data[__UUID.tag] = service
		
		__Nick = PBField.new("Nick", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __Nick
		data[__Nick.tag] = service
		
		var __AssetIDRecordMap_default: Array = []
		__AssetIDRecordMap = PBField.new("AssetIDRecordMap", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 10, true, __AssetIDRecordMap_default)
		service = PBServiceField.new()
		service.field = __AssetIDRecordMap
		service.func_ref = Callable(self, "add_empty_AssetIDRecordMap")
		data[__AssetIDRecordMap.tag] = service
		
		var __RecordMap_default: Array = []
		__RecordMap = PBField.new("RecordMap", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 1000, true, __RecordMap_default)
		service = PBServiceField.new()
		service.field = __RecordMap
		service.func_ref = Callable(self, "add_empty_RecordMap")
		data[__RecordMap.tag] = service
		
		var __PetRecordMap_default: Array = []
		__PetRecordMap = PBField.new("PetRecordMap", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 2000, true, __PetRecordMap_default)
		service = PBServiceField.new()
		service.field = __PetRecordMap
		service.func_ref = Callable(self, "add_empty_PetRecordMap")
		data[__PetRecordMap.tag] = service
		
	var data = {}
	
	var __UUID: PBField
	func has_UUID() -> bool:
		if __UUID.value != null:
			return true
		return false
	func get_UUID() -> int:
		return __UUID.value
	func clear_UUID() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__UUID.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
	func set_UUID(value : int) -> void:
		__UUID.value = value
	
	var __Nick: PBField
	func has_Nick() -> bool:
		if __Nick.value != null:
			return true
		return false
	func get_Nick() -> String:
		return __Nick.value
	func clear_Nick() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__Nick.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_Nick(value : String) -> void:
		__Nick.value = value
	
	var __AssetIDRecordMap: PBField
	func get_raw_AssetIDRecordMap():
		return __AssetIDRecordMap.value
	func get_AssetIDRecordMap():
		return PBPacker.construct_map(__AssetIDRecordMap.value)
	func clear_AssetIDRecordMap():
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__AssetIDRecordMap.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_AssetIDRecordMap() -> CharacterRecord.map_type_AssetIDRecordMap:
		var element = CharacterRecord.map_type_AssetIDRecordMap.new()
		__AssetIDRecordMap.value.append(element)
		return element
	func add_AssetIDRecordMap(a_key, a_value) -> void:
		var idx = -1
		for i in range(__AssetIDRecordMap.value.size()):
			if __AssetIDRecordMap.value[i].get_key() == a_key:
				idx = i
				break
		var element = CharacterRecord.map_type_AssetIDRecordMap.new()
		element.set_key(a_key)
		element.set_value(a_value)
		if idx != -1:
			__AssetIDRecordMap.value[idx] = element
		else:
			__AssetIDRecordMap.value.append(element)
	
	var __RecordMap: PBField
	func get_raw_RecordMap():
		return __RecordMap.value
	func get_RecordMap():
		return PBPacker.construct_map(__RecordMap.value)
	func clear_RecordMap():
		data[1000].state = PB_SERVICE_STATE.UNFILLED
		__RecordMap.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_RecordMap() -> CharacterRecord.map_type_RecordMap:
		var element = CharacterRecord.map_type_RecordMap.new()
		__RecordMap.value.append(element)
		return element
	func add_RecordMap(a_key) -> RecordPrimary:
		var idx = -1
		for i in range(__RecordMap.value.size()):
			if __RecordMap.value[i].get_key() == a_key:
				idx = i
				break
		var element = CharacterRecord.map_type_RecordMap.new()
		element.set_key(a_key)
		if idx != -1:
			__RecordMap.value[idx] = element
		else:
			__RecordMap.value.append(element)
		return element.new_value()
	
	var __PetRecordMap: PBField
	func get_raw_PetRecordMap():
		return __PetRecordMap.value
	func get_PetRecordMap():
		return PBPacker.construct_map(__PetRecordMap.value)
	func clear_PetRecordMap():
		data[2000].state = PB_SERVICE_STATE.UNFILLED
		__PetRecordMap.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_PetRecordMap() -> CharacterRecord.map_type_PetRecordMap:
		var element = CharacterRecord.map_type_PetRecordMap.new()
		__PetRecordMap.value.append(element)
		return element
	func add_PetRecordMap(a_key) -> PetRecord:
		var idx = -1
		for i in range(__PetRecordMap.value.size()):
			if __PetRecordMap.value[i].get_key() == a_key:
				idx = i
				break
		var element = CharacterRecord.map_type_PetRecordMap.new()
		element.set_key(a_key)
		if idx != -1:
			__PetRecordMap.value[idx] = element
		else:
			__PetRecordMap.value.append(element)
		return element.new_value()
	
	class map_type_AssetIDRecordMap:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			if __key.value != null:
				return true
			return false
		func get_key() -> int:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
		func set_key(value : int) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			if __value.value != null:
				return true
			return false
		func get_value() -> int:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
		func set_value(value : int) -> void:
			__value.value = value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	class map_type_RecordMap:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			service.func_ref = Callable(self, "new_value")
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			if __key.value != null:
				return true
			return false
		func get_key() -> int:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
		func set_key(value : int) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			if __value.value != null:
				return true
			return false
		func get_value() -> RecordPrimary:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		func new_value() -> RecordPrimary:
			__value.value = RecordPrimary.new()
			return __value.value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	class map_type_PetRecordMap:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			service.func_ref = Callable(self, "new_value")
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			if __key.value != null:
				return true
			return false
		func get_key() -> int:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
		func set_key(value : int) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			if __value.value != null:
				return true
			return false
		func get_value() -> PetRecord:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		func new_value() -> PetRecord:
			__value.value = PetRecord.new()
			return __value.value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class RecordPrimary:
	extends RefCounted
	func _init():
		var service
		
		__PrimaryID = PBField.new("PrimaryID", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
		service = PBServiceField.new()
		service.field = __PrimaryID
		data[__PrimaryID.tag] = service
		
		var __RecordElementMap_default: Array = []
		__RecordElementMap = PBField.new("RecordElementMap", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 2, true, __RecordElementMap_default)
		service = PBServiceField.new()
		service.field = __RecordElementMap
		service.func_ref = Callable(self, "add_empty_RecordElementMap")
		data[__RecordElementMap.tag] = service
		
	var data = {}
	
	var __PrimaryID: PBField
	func has_PrimaryID() -> bool:
		if __PrimaryID.value != null:
			return true
		return false
	func get_PrimaryID() -> int:
		return __PrimaryID.value
	func clear_PrimaryID() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__PrimaryID.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
	func set_PrimaryID(value : int) -> void:
		__PrimaryID.value = value
	
	var __RecordElementMap: PBField
	func get_raw_RecordElementMap():
		return __RecordElementMap.value
	func get_RecordElementMap():
		return PBPacker.construct_map(__RecordElementMap.value)
	func clear_RecordElementMap():
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__RecordElementMap.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_RecordElementMap() -> RecordPrimary.map_type_RecordElementMap:
		var element = RecordPrimary.map_type_RecordElementMap.new()
		__RecordElementMap.value.append(element)
		return element
	func add_RecordElementMap(a_key) -> RecordSecondary:
		var idx = -1
		for i in range(__RecordElementMap.value.size()):
			if __RecordElementMap.value[i].get_key() == a_key:
				idx = i
				break
		var element = RecordPrimary.map_type_RecordElementMap.new()
		element.set_key(a_key)
		if idx != -1:
			__RecordElementMap.value[idx] = element
		else:
			__RecordElementMap.value.append(element)
		return element.new_value()
	
	class map_type_RecordElementMap:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			service.func_ref = Callable(self, "new_value")
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			if __key.value != null:
				return true
			return false
		func get_key() -> int:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
		func set_key(value : int) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			if __value.value != null:
				return true
			return false
		func get_value() -> RecordSecondary:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		func new_value() -> RecordSecondary:
			__value.value = RecordSecondary.new()
			return __value.value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class RecordSecondary:
	extends RefCounted
	func _init():
		var service
		
		__SecondaryID = PBField.new("SecondaryID", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
		service = PBServiceField.new()
		service.field = __SecondaryID
		data[__SecondaryID.tag] = service
		
		__timestamp = PBField.new("timestamp", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __timestamp
		data[__timestamp.tag] = service
		
		var __Data_default: Array[int] = []
		__Data = PBField.new("Data", PB_DATA_TYPE.UINT64, PB_RULE.REPEATED, 3, true, __Data_default)
		service = PBServiceField.new()
		service.field = __Data
		data[__Data.tag] = service
		
		var __StrData_default: Array[String] = []
		__StrData = PBField.new("StrData", PB_DATA_TYPE.STRING, PB_RULE.REPEATED, 4, true, __StrData_default)
		service = PBServiceField.new()
		service.field = __StrData
		data[__StrData.tag] = service
		
	var data = {}
	
	var __SecondaryID: PBField
	func has_SecondaryID() -> bool:
		if __SecondaryID.value != null:
			return true
		return false
	func get_SecondaryID() -> int:
		return __SecondaryID.value
	func clear_SecondaryID() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__SecondaryID.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
	func set_SecondaryID(value : int) -> void:
		__SecondaryID.value = value
	
	var __timestamp: PBField
	func has_timestamp() -> bool:
		if __timestamp.value != null:
			return true
		return false
	func get_timestamp() -> int:
		return __timestamp.value
	func clear_timestamp() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__timestamp.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_timestamp(value : int) -> void:
		__timestamp.value = value
	
	var __Data: PBField
	func get_Data() -> Array[int]:
		return __Data.value
	func clear_Data() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__Data.value.clear()
	func add_Data(value : int) -> void:
		__Data.value.append(value)
	
	var __StrData: PBField
	func get_StrData() -> Array[String]:
		return __StrData.value
	func clear_StrData() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__StrData.value.clear()
	func add_StrData(value : String) -> void:
		__StrData.value.append(value)
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
enum PetAction {
	PetAction_Unknow = 0,
	PetAction_Attack = 1,
	PetAction_Faint = 2,
	PetAction_Hurt = 3,
	PetAction_Defense = 4,
	PetAction_Stand = 5,
	PetAction_Walk = 6,
	PetAction_AttackShort = 7,
	PetAction_Max = 8
}

enum PetRarity {
	PetRarity_Unknow = 0,
	PetRarity_Common = 1,
	PetRarity_Rare = 2,
	PetRarity_Epic = 3,
	PetRarity_Legendary = 4,
	PetRarity_Mythic = 5,
	PetRarity_Max = 6
}

enum PetGrade {
	PetGrade_Unknow = 0,
	PetGrade_Common = 1,
	PetGrade_Rare = 2,
	PetGrade_Epic = 3,
	PetGrade_Legendary = 4,
	PetGrade_Mythic = 5,
	PetGrade_Max = 6
}

class PetRecord:
	extends RefCounted
	func _init():
		var service
		
		__UUID = PBField.new("UUID", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
		service = PBServiceField.new()
		service.field = __UUID
		data[__UUID.tag] = service
		
		__Nick = PBField.new("Nick", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __Nick
		data[__Nick.tag] = service
		
		var __AssetRecordBaseMap_default: Array = []
		__AssetRecordBaseMap = PBField.new("AssetRecordBaseMap", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 10, true, __AssetRecordBaseMap_default)
		service = PBServiceField.new()
		service.field = __AssetRecordBaseMap
		service.func_ref = Callable(self, "add_empty_AssetRecordBaseMap")
		data[__AssetRecordBaseMap.tag] = service
		
		var __RecordMap_default: Array = []
		__RecordMap = PBField.new("RecordMap", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 1000, true, __RecordMap_default)
		service = PBServiceField.new()
		service.field = __RecordMap
		service.func_ref = Callable(self, "add_empty_RecordMap")
		data[__RecordMap.tag] = service
		
	var data = {}
	
	var __UUID: PBField
	func has_UUID() -> bool:
		if __UUID.value != null:
			return true
		return false
	func get_UUID() -> int:
		return __UUID.value
	func clear_UUID() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__UUID.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
	func set_UUID(value : int) -> void:
		__UUID.value = value
	
	var __Nick: PBField
	func has_Nick() -> bool:
		if __Nick.value != null:
			return true
		return false
	func get_Nick() -> String:
		return __Nick.value
	func clear_Nick() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__Nick.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_Nick(value : String) -> void:
		__Nick.value = value
	
	var __AssetRecordBaseMap: PBField
	func get_raw_AssetRecordBaseMap():
		return __AssetRecordBaseMap.value
	func get_AssetRecordBaseMap():
		return PBPacker.construct_map(__AssetRecordBaseMap.value)
	func clear_AssetRecordBaseMap():
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__AssetRecordBaseMap.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_AssetRecordBaseMap() -> PetRecord.map_type_AssetRecordBaseMap:
		var element = PetRecord.map_type_AssetRecordBaseMap.new()
		__AssetRecordBaseMap.value.append(element)
		return element
	func add_AssetRecordBaseMap(a_key, a_value) -> void:
		var idx = -1
		for i in range(__AssetRecordBaseMap.value.size()):
			if __AssetRecordBaseMap.value[i].get_key() == a_key:
				idx = i
				break
		var element = PetRecord.map_type_AssetRecordBaseMap.new()
		element.set_key(a_key)
		element.set_value(a_value)
		if idx != -1:
			__AssetRecordBaseMap.value[idx] = element
		else:
			__AssetRecordBaseMap.value.append(element)
	
	var __RecordMap: PBField
	func get_raw_RecordMap():
		return __RecordMap.value
	func get_RecordMap():
		return PBPacker.construct_map(__RecordMap.value)
	func clear_RecordMap():
		data[1000].state = PB_SERVICE_STATE.UNFILLED
		__RecordMap.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_RecordMap() -> PetRecord.map_type_RecordMap:
		var element = PetRecord.map_type_RecordMap.new()
		__RecordMap.value.append(element)
		return element
	func add_RecordMap(a_key) -> RecordPrimary:
		var idx = -1
		for i in range(__RecordMap.value.size()):
			if __RecordMap.value[i].get_key() == a_key:
				idx = i
				break
		var element = PetRecord.map_type_RecordMap.new()
		element.set_key(a_key)
		if idx != -1:
			__RecordMap.value[idx] = element
		else:
			__RecordMap.value.append(element)
		return element.new_value()
	
	class map_type_AssetRecordBaseMap:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			if __key.value != null:
				return true
			return false
		func get_key() -> int:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
		func set_key(value : int) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			if __value.value != null:
				return true
			return false
		func get_value() -> int:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
		func set_value(value : int) -> void:
			__value.value = value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	class map_type_RecordMap:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			service.func_ref = Callable(self, "new_value")
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			if __key.value != null:
				return true
			return false
		func get_key() -> int:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
		func set_key(value : int) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			if __value.value != null:
				return true
			return false
		func get_value() -> RecordPrimary:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		func new_value() -> RecordPrimary:
			__value.value = RecordPrimary.new()
			return __value.value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
enum AssetType {
	AssetType_Record = 0,
	AssetType_Character = 1,
	AssetType_Map = 2,
	AssetType_Item = 3,
	AssetType_Pet = 4,
	AssetType_NPC = 5,
	AssetType_Decoration = 6,
	AssetType_Building = 7,
	AssetType_Plant = 8
}

enum AssetIDRange {
	AssetIDRange_Unknow = 0,
	AssetIDRange_Record_Start = 1,
	AssetIDRange_Record_End = 1000000,
	AssetIDRange_Character_Start = 1000001,
	AssetIDRange_Character_End = 1999999,
	AssetIDRange_Map_Start = 2000001,
	AssetIDRange_Map_End = 2999999,
	AssetIDRange_Item_Start = 3000001,
	AssetIDRange_Item_End = 3999999,
	AssetIDRange_Pet_Start = 4000001,
	AssetIDRange_Pet_End = 4999999,
	AssetIDRange_NPC_Start = 5000001,
	AssetIDRange_NPC_End = 5999999,
	AssetIDRange_Decoration_Start = 6000001,
	AssetIDRange_Decoration_End = 6999999,
	AssetIDRange_Building_Start = 7000001,
	AssetIDRange_Building_End = 7999999,
	AssetIDRange_Plant_Start = 8000001,
	AssetIDRange_Plant_End = 8999999
}

enum AssetIDRecord {
	AssetIDRecord_Unknow = 0,
	AssetIDRecord_AssetID = 1,
	AssetIDRecord_Exp = 2,
	AssetIDRecord_HP = 3,
	AssetIDRecord_MP = 4,
	AssetIDRecord_CreateTimestamp = 5,
	AssetIDRecord_MapID = 7,
	AssetIDRecord_Direction = 10,
	AssetIDRecord_Action = 11,
	AssetIDRecord_RebirthCount = 13,
	AssetIDRecord_ElementalEarth = 101,
	AssetIDRecord_ElementalWater = 102,
	AssetIDRecord_ElementalFire = 103,
	AssetIDRecord_ElementalWind = 104,
	AssetIDRecord_Character_LastLoginTimestamp = 1001,
	AssetIDRecord_Character_LastLogoutTimestamp = 1002,
	AssetIDRecord_Character_AvailablePoint = 1003,
	AssetIDRecord_Character_AttributesStrength = 1101,
	AssetIDRecord_Character_AttributesEndurance = 1102,
	AssetIDRecord_Character_AttributesAgility = 1103,
	AssetIDRecord_Character_AttributesStamina = 1104,
	AssetIDRecord_Pet_AttributesAttack = 2001,
	AssetIDRecord_Pet_AttributesDefense = 2002,
	AssetIDRecord_Pet_AttributesAgility = 2003,
	AssetIDRecord_Pet_AttributesHP = 2004,
	AssetIDRecord_Pet_Loyalty = 2005,
	AssetIDRecord_Pet_AttributesLevel_InitialStats = 2101,
	AssetIDRecord_Pet_AttributesAttack_InitialStats = 2102,
	AssetIDRecord_Pet_AttributesDefense_InitialStats = 2103,
	AssetIDRecord_Pet_AttributesAgility_InitialStats = 2104,
	AssetIDRecord_Pet_AttributesHP_InitialStats = 2105
}

enum AssetDirection {
	AssetDirection_Unknow = 0,
	AssetDirection_Up = 1,
	AssetDirection_UpRight = 2,
	AssetDirection_Right = 3,
	AssetDirection_DownRight = 4,
	AssetDirection_Down = 5,
	AssetDirection_DownLeft = 6,
	AssetDirection_Left = 7,
	AssetDirection_UpLeft = 8,
	AssetDirection_Max = 9
}

enum CombatEnemyGroupEnemyCountRange {
	CombatEnemyGroupEnemyCountRange_Unknow = 0,
	CombatEnemyGroupEnemyCountRange_Min = 1,
	CombatEnemyGroupEnemyCountRange_Max = 10
}

enum CombatEnemyGroupBabyRate {
	CombatEnemyGroupBabyRate_Min = 0,
	CombatEnemyGroupBabyRate_Max = 100000
}

class KV:
	extends RefCounted
	func _init():
		var service
		
		__Key = PBField.new("Key", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __Key
		data[__Key.tag] = service
		
		__Value = PBField.new("Value", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __Value
		data[__Value.tag] = service
		
	var data = {}
	
	var __Key: PBField
	func has_Key() -> bool:
		if __Key.value != null:
			return true
		return false
	func get_Key() -> int:
		return __Key.value
	func clear_Key() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__Key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_Key(value : int) -> void:
		__Key.value = value
	
	var __Value: PBField
	func has_Value() -> bool:
		if __Value.value != null:
			return true
		return false
	func get_Value() -> int:
		return __Value.value
	func clear_Value() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__Value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_Value(value : int) -> void:
		__Value.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class Rect:
	extends RefCounted
	func _init():
		var service
		
		__Pos = PBField.new("Pos", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __Pos
		service.func_ref = Callable(self, "new_Pos")
		data[__Pos.tag] = service
		
		__Width = PBField.new("Width", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __Width
		data[__Width.tag] = service
		
		__Height = PBField.new("Height", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __Height
		data[__Height.tag] = service
		
	var data = {}
	
	var __Pos: PBField
	func has_Pos() -> bool:
		if __Pos.value != null:
			return true
		return false
	func get_Pos() -> Point:
		return __Pos.value
	func clear_Pos() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__Pos.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_Pos() -> Point:
		__Pos.value = Point.new()
		return __Pos.value
	
	var __Width: PBField
	func has_Width() -> bool:
		if __Width.value != null:
			return true
		return false
	func get_Width() -> int:
		return __Width.value
	func clear_Width() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__Width.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_Width(value : int) -> void:
		__Width.value = value
	
	var __Height: PBField
	func has_Height() -> bool:
		if __Height.value != null:
			return true
		return false
	func get_Height() -> int:
		return __Height.value
	func clear_Height() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__Height.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_Height(value : int) -> void:
		__Height.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class Point:
	extends RefCounted
	func _init():
		var service
		
		__X = PBField.new("X", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __X
		data[__X.tag] = service
		
		__Y = PBField.new("Y", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __Y
		data[__Y.tag] = service
		
	var data = {}
	
	var __X: PBField
	func has_X() -> bool:
		if __X.value != null:
			return true
		return false
	func get_X() -> int:
		return __X.value
	func clear_X() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__X.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_X(value : int) -> void:
		__X.value = value
	
	var __Y: PBField
	func has_Y() -> bool:
		if __Y.value != null:
			return true
		return false
	func get_Y() -> int:
		return __Y.value
	func clear_Y() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__Y.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_Y(value : int) -> void:
		__Y.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
enum LevelRange {
	LevelRange_Unknow = 0,
	LevelRange_Min = 1,
	LevelRange_Max = 140
}

enum EquipmentType {
	EquipmentType_Unknow = 0,
	EquipmentType_Necklace = 1,
	EquipmentType_Helmet = 2,
	EquipmentType_Ring = 3,
	EquipmentType_Weapon = 4,
	EquipmentType_Chest = 5,
	EquipmentType_Shield = 6,
	EquipmentType_Gloves = 7,
	EquipmentType_Belt = 8,
	EquipmentType_Boots = 9,
	EquipmentType_Max = 10
}

class EquipmentRecord:
	extends RefCounted
	func _init():
		var service
		
		__UUID = PBField.new("UUID", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
		service = PBServiceField.new()
		service.field = __UUID
		data[__UUID.tag] = service
		
		var __RecordBaseMap_default: Array = []
		__RecordBaseMap = PBField.new("RecordBaseMap", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 10, true, __RecordBaseMap_default)
		service = PBServiceField.new()
		service.field = __RecordBaseMap
		service.func_ref = Callable(self, "add_empty_RecordBaseMap")
		data[__RecordBaseMap.tag] = service
		
		var __RecordMap_default: Array = []
		__RecordMap = PBField.new("RecordMap", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 1000, true, __RecordMap_default)
		service = PBServiceField.new()
		service.field = __RecordMap
		service.func_ref = Callable(self, "add_empty_RecordMap")
		data[__RecordMap.tag] = service
		
	var data = {}
	
	var __UUID: PBField
	func has_UUID() -> bool:
		if __UUID.value != null:
			return true
		return false
	func get_UUID() -> int:
		return __UUID.value
	func clear_UUID() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__UUID.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
	func set_UUID(value : int) -> void:
		__UUID.value = value
	
	var __RecordBaseMap: PBField
	func get_raw_RecordBaseMap():
		return __RecordBaseMap.value
	func get_RecordBaseMap():
		return PBPacker.construct_map(__RecordBaseMap.value)
	func clear_RecordBaseMap():
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__RecordBaseMap.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_RecordBaseMap() -> EquipmentRecord.map_type_RecordBaseMap:
		var element = EquipmentRecord.map_type_RecordBaseMap.new()
		__RecordBaseMap.value.append(element)
		return element
	func add_RecordBaseMap(a_key, a_value) -> void:
		var idx = -1
		for i in range(__RecordBaseMap.value.size()):
			if __RecordBaseMap.value[i].get_key() == a_key:
				idx = i
				break
		var element = EquipmentRecord.map_type_RecordBaseMap.new()
		element.set_key(a_key)
		element.set_value(a_value)
		if idx != -1:
			__RecordBaseMap.value[idx] = element
		else:
			__RecordBaseMap.value.append(element)
	
	var __RecordMap: PBField
	func get_raw_RecordMap():
		return __RecordMap.value
	func get_RecordMap():
		return PBPacker.construct_map(__RecordMap.value)
	func clear_RecordMap():
		data[1000].state = PB_SERVICE_STATE.UNFILLED
		__RecordMap.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_RecordMap() -> EquipmentRecord.map_type_RecordMap:
		var element = EquipmentRecord.map_type_RecordMap.new()
		__RecordMap.value.append(element)
		return element
	func add_RecordMap(a_key) -> RecordPrimary:
		var idx = -1
		for i in range(__RecordMap.value.size()):
			if __RecordMap.value[i].get_key() == a_key:
				idx = i
				break
		var element = EquipmentRecord.map_type_RecordMap.new()
		element.set_key(a_key)
		if idx != -1:
			__RecordMap.value[idx] = element
		else:
			__RecordMap.value.append(element)
		return element.new_value()
	
	class map_type_RecordBaseMap:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.UINT64, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			if __key.value != null:
				return true
			return false
		func get_key() -> int:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
		func set_key(value : int) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			if __value.value != null:
				return true
			return false
		func get_value() -> int:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT64]
		func set_value(value : int) -> void:
			__value.value = value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	class map_type_RecordMap:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			service.func_ref = Callable(self, "new_value")
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			if __key.value != null:
				return true
			return false
		func get_key() -> int:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
		func set_key(value : int) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			if __value.value != null:
				return true
			return false
		func get_value() -> RecordPrimary:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		func new_value() -> RecordPrimary:
			__value.value = RecordPrimary.new()
			return __value.value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
enum EquipmentRecordBase {
	EquipmentRecordBase_Unknow = 0,
	EquipmentRecordBase_DamagePercent = 10000,
	EquipmentRecordBase_CritRate = 10001,
	EquipmentRecordBase_CritDamageBonusRate = 10002
}

enum EquipmentRecordPrimary {
	EquipmentRecordPrimary_Unknow = 0,
	EquipmentRecordPrimary_Slot = 1
}

enum EquipmentRecordSecondary {
	EquipmentRecordSecondary_Unknow = 0,
	EquipmentRecordSecondary_Slot_Data = 1
}

enum CharacterWeaponType {
	CharacterWeaponType_Unknow = 0,
	CharacterWeaponType_Unarmed = 1,
	CharacterWeaponType_Axe = 2,
	CharacterWeaponType_Bow = 3,
	CharacterWeaponType_Spear = 4,
	CharacterWeaponType_Stick = 5,
	CharacterWeaponType_Max = 6
}

################ USER DATA END #################
